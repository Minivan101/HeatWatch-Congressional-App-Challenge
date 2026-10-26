import json,urllib.request,urllib.parse,datetime,hashlib
from pathlib import Path
bounds={'south':36.04,'north':36.34,'west':-115.38,'east':-115.04}
query='[out:json][timeout:90][maxsize:268435456];(way["building"](36.04,-115.38,36.34,-115.04);relation["building"](36.04,-115.38,36.34,-115.04););out geom;'
request=urllib.request.Request('https://overpass-api.de/api/interpreter',data=urllib.parse.urlencode({'data':query}).encode(),headers={'User-Agent':'HeatWatch/0.1 (Las Vegas student prototype data preparation)'})
raw=urllib.request.urlopen(request,timeout=120).read()
data=json.loads(raw)
if data.get('remark') or not isinstance(data.get('elements'), list):
 raise RuntimeError('Overpass returned an incomplete or invalid extraction; existing asset kept.')
buildings=[];gaps=[]
def height(tags):
 try:
  value=str(tags.get('height','')).strip().lower();h=float(value.removesuffix(' m').removesuffix('m')) if value else None
  if any(k in tags for k in ('min_height','building:min_level','building:part')): return None
  return h if h and 0<h<=500 else None
 except ValueError:return None
for e in data['elements']:
 geom=e.get('geometry',[]);tags=e.get('tags',{})
 if e['type']=='way' and len(geom)>=4 and geom[0]==geom[-1]:
  h=height(tags);buildings.append({'osmId':f"way/{e['id']}",'footprint':[{'latitude':p['lat'],'longitude':p['lon']} for p in geom[:-1]],'heightMeters':h,'heightSource':'height' if h is not None else 'unknown'})
 else:
  b=e.get('bounds')
  if b:gaps.append({'osmId':f"{e['type']}/{e['id']}",'bounds':{'south':b['minlat'],'north':b['maxlat'],'west':b['minlon'],'east':b['maxlon']}})
output={'schemaVersion':1,'bounds':bounds,'buildings':buildings,'coverageGaps':gaps,'sourceUrl':'https://overpass-api.de/api/interpreter','query':query,'retrievedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceSha256':hashlib.sha256(raw).hexdigest(),'attribution':'© OpenStreetMap contributors','licenseUrl':'https://www.openstreetmap.org/copyright','limitations':'Flat buildings with explicit metre heights only. Missing heights, unsupported relations, trees and terrain are excluded.'}
output['mappedBuildingCount']=len(buildings)
output['missingHeightCount']=sum(b['heightMeters'] is None for b in buildings)
output['buildings']=[b for b in buildings if b['heightMeters'] is not None]
target=Path(__file__).resolve().parents[1] / 'data/buildings/las_vegas';target.mkdir(exist_ok=True)
(target/'buildings.json').write_text(json.dumps(output,separators=(',',':'))+'\n')
print(json.dumps({'buildings':len(buildings),'heights':sum(b['heightMeters'] is not None for b in buildings),'gaps':len(gaps),'bytes':len(raw)}))
