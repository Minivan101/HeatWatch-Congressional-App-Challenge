'prepare building and tree data'

import argparse,csv,datetime,gzip,hashlib,io,json,math,pathlib,urllib.request
import numpy as np
import rasterio
from rasterio.windows import from_bounds
from rasterio.warp import reproject,Resampling
from rasterio.transform import from_origin
from shapely.geometry import shape,box
R=6378137.0; CELL=5; N=512; SPAN=CELL*N
BOUNDS={'south':36.036,'north':36.404,'west':-115.504,'east':-115.036}
def xy(lon,lat):return R*math.radians(lon),R*math.log(math.tan(math.pi/4+math.radians(lat)/2))
def quad(lon,lat,z):
 x=int((lon+180)/360*2**z);y=int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*2**z)
 return ''.join(str(((x>>b)&1)+2*((y>>b)&1)) for b in range(z-1,-1,-1))
def download(url,target):
 if not target.exists():
  tmp=target.with_suffix(target.suffix+'.part')
  with urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'HeatWatch student prototype data preparation'}),timeout=90) as r,tmp.open('wb') as f:
   while chunk:=r.read(1024*1024):f.write(chunk)
  tmp.replace(target)
 return {'url':url,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--output',required=True);ap.add_argument('--cache',default='/private/tmp/heatwatch-shade-cache');a=ap.parse_args()
 out=pathlib.Path(a.output);out.mkdir(parents=True,exist_ok=True);cache=pathlib.Path(a.cache);cache.mkdir(parents=True,exist_ok=True)
 left,bottom=xy(BOUNDS['west'],BOUNDS['south']);right,top=xy(BOUNDS['east'],BOUNDS['north']);ix0,ix1=math.floor(left/SPAN),math.floor(right/SPAN);iy0,iy1=math.floor(bottom/SPAN),math.floor(top/SPAN)
 tiles={f'{x}_{y}':{'x':x*SPAN,'y':(y+1)*SPAN,'buildings':[]} for x in range(ix0,ix1+1) for y in range(iy0,iy1+1)}
 clip=box(BOUNDS['west'],BOUNDS['south'],BOUNDS['east'],BOUNDS['north']);sources=[];counts={'footprints':0,'heights':0,'missingHeights':0,'invalid':0};gaps=[]
 index='https://bfppub.blob.core.windows.net/%24web/2026-08-13/dataset-links.csv';indexraw=urllib.request.urlopen(index,timeout=60).read();rows=list(csv.DictReader(io.StringIO(indexraw.decode())));qs={quad(lon,lat,9) for lon in [BOUNDS['west'],BOUNDS['east']] for lat in [BOUNDS['south'],BOUNDS['north']]};seen=set()
 for row in rows:
  if row['Location']!='UnitedStates' or row['QuadKey'] not in qs:continue
  path=cache/(row['QuadKey']+'.geojsonl.gz')
  if row['QuadKey']=='023013100' and not path.exists() and pathlib.Path('/private/tmp/heatwatch-ms-vegas.geojsonl.gz').exists():path.write_bytes(pathlib.Path('/private/tmp/heatwatch-ms-vegas.geojsonl.gz').read_bytes())
  source=download(row['Url'],path);source['kind']='Microsoft buildings';sources.append(source);print('Downloaded building tile',row['QuadKey'],flush=True)
  with gzip.open(path,'rt') as f:
   for line in f:
    d=json.loads(line);geom=d['geometry']
    if geom['type']!='Polygon':continue
    ring=geom['coordinates'][0];lons=[p[0] for p in ring];lats=[p[1] for p in ring];w,e,s,n=min(lons),max(lons),min(lats),max(lats)
    if e<BOUNDS['west'] or w>BOUNDS['east'] or n<BOUNDS['south'] or s>BOUNDS['north']:continue
    polygon=shape(geom)
    if not polygon.is_valid or polygon.is_empty:
     counts['invalid']+=1;gaps.append([w,s,e,n]);continue
    if not polygon.intersects(clip):continue
    rings=[[[round(p[0],7),round(p[1],7)] for p in r[:-1]] for r in geom['coordinates']]
    fingerprint=json.dumps(rings,separators=(',',':'))
    if fingerprint in seen:continue
    seen.add(fingerprint);h=d['properties'].get('height',-1);h=round(h,2) if isinstance(h,(int,float)) and math.isfinite(h) and 0<h<=500 else None
    h=h if h and h>0 else None
    counts['footprints']+=1;counts['heights' if h else 'missingHeights']+=1
    b=[h,rings,d['properties'].get('confidence',-1)]
    x0,y0=xy(w,s);x1,y1=xy(e,n)
    for x in range(max(ix0,math.floor(x0/SPAN)),min(ix1,math.floor(x1/SPAN))+1):
     for y in range(max(iy0,math.floor(y0/SPAN)),min(iy1,math.floor(y1/SPAN))+1):tiles[f'{x}_{y}']['buildings'].append(b)
 print('Buildings',counts,flush=True)
 for key,tile in tiles.items():
  target=out/(key+'.buildings.json.gz');target.write_bytes(gzip.compress(json.dumps(tile['buildings'],separators=(',',':')).encode(),mtime=0));tile['buildings']=target.name
 base='https://dataforgood-fb-data.s3.amazonaws.com/forests/v2/global/dinov3_global_chm_v2_ml3/'
 canopyqs={quad(lon,lat,10) for lon in [BOUNDS['west'],BOUNDS['east']] for lat in [BOUNDS['south'],BOUNDS['north']]};rasters=[]
 for q in sorted(canopyqs):
  target=cache/(q+'.tif');source=download(base+'chm/'+q+'.tif',target);source['kind']='Meta WRI CHMv2';sources.append(source);rasters.append(rasterio.open(target));print('Downloaded canopy',q,source['bytes'],flush=True)
  meta=cache/(q+'.metadata.geojson')
  try:sources.append(dict(download(base+'metadata/'+q+'.geojson',meta),kind='Canopy observation dates'))
  except urllib.error.HTTPError as e:print('Observation metadata unavailable',q,e.code,flush=True)
 valid=tree=0
 for key,tile in tiles.items():
  dest=np.full((N,N),255,dtype='uint8');transform=from_origin(tile['x'],tile['y'],CELL,CELL)
  for src in rasters:
   w=max(tile['x'],src.bounds.left);e=min(tile['x']+SPAN,src.bounds.right);s=max(tile['y']-SPAN,src.bounds.bottom);n=min(tile['y'],src.bounds.top)
   if w>=e or s>=n:continue
   win=from_bounds(w,s,e,n,src.transform).round_offsets().round_lengths();data=src.read(1,window=win,masked=True).filled(255)

   layer=np.full((N,N),255,dtype='uint8')
   reproject(source=data,destination=layer,src_transform=src.window_transform(win),src_crs=src.crs,src_nodata=255,dst_transform=transform,dst_crs='EPSG:3857',dst_nodata=255,resampling=Resampling.nearest)
   good=layer!=255;dest[good]=layer[good]

  xs=tile['x']+(np.arange(N)+.5)*CELL;ys=tile['y']-(np.arange(N)+.5)*CELL;inside=(ys[:,None]>=bottom)&(ys[:,None]<=top)&(xs[None,:]>=left)&(xs[None,:]<=right);dest[~inside]=255
  valid+=int(np.count_nonzero(dest!=255));tree+=int(np.count_nonzero((dest>=2)&(dest<255)))
  target=out/(key+'.canopy.bin.gz');target.write_bytes(gzip.compress(dest.tobytes(),mtime=0));tile['canopy']=target.name;tile['buildingSha256']=hashlib.sha256((out/tile['buildings']).read_bytes()).hexdigest();tile['canopySha256']=hashlib.sha256(target.read_bytes()).hexdigest()
 for src in rasters:src.close()
 manifest={'schemaVersion':1,'bounds':BOUNDS,'crs':'EPSG:3857','cellMeters':CELL,'tilePixels':N,'shadowLimitMeters':250,'canopyMinimumMeters':2,'retrievedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'buildingCounts':counts,'canopyValidCells':valid,'canopyCellsAtLeast2m':tree,'coverageGaps':gaps,'sources':sources,'tiles':tiles,'licenses':[{'name':'Microsoft Global ML Building Footprints','license':'CDLA Permissive 2.0','url':'https://cdla.dev/permissive-2-0/'},{'name':'Meta and WRI 2026 CHMv2, source imagery Vantor','license':'CC BY 4.0','url':'https://creativecommons.org/licenses/by/4.0/'}],'processing':'Full polygons and holes; missing building heights null. Canopy resampled nearest to 5 EPSG:3857 metres (~4 ground metres at Vegas), height metres quantized by provider; cloud/unavailable =255, valid no-canopy=0. Model assumes opaque vegetation below canopy surface; not measured shade or UV dose.'}
 dates={}
 for meta in cache.glob('*.metadata.geojson'):
  raw=json.loads(meta.read_text());dates[meta.name]=sorted({f['properties'].get('acq_date') for f in raw['features'] if shape(f['geometry']).intersects(clip)})
 manifest['canopyObservationDatesIntersectingExtract']=dates
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');(out/'CDLA-Permissive-2.0.txt').write_bytes(urllib.request.urlopen('https://raw.githubusercontent.com/microsoft/GlobalMLBuildingFootprints/main/LICENSE',timeout=30).read())
 print('DONE',counts,'valid canopy cells',valid,'tree cells',tree,'packaged bytes',sum(p.stat().st_size for p in out.iterdir()),flush=True)
if __name__=='__main__':main()
