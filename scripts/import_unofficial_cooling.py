import json, re, html, hashlib, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
RAW=ROOT/'data/cooling_centers/unofficial_sources'
DEST=ROOT/'data/cooling_centers/unofficial_sources'
DEST.mkdir(parents=True,exist_ok=True)
CITY='https://mapdata.lasvegasnevada.gov/clvgis/rest/services/ExistingInfrastructure/Public_Park_Amenities/MapServer/8'
PARK='https://services1.arcgis.com/F1v0ufATbBQScMtY/ArcGIS/rest/services/Parks_Facilities_Merge/FeatureServer/4'
SOURCES=[dict(id='city-fountains',title='City of Las Vegas drinking-fountain inventory',url=CITY),dict(id='city-parks',title='City of Las Vegas park addresses',url=PARK),dict(id='mall-operator',title='Las Vegas South Premium Outlets visitor information',url='https://www.premiumoutlets.com/outlet/las-vegas-south/about'),dict(id='mall-coordinate',title='OpenStreetMap mall location',url='https://www.openstreetmap.org/way/38358961')]
normalize=lambda s: re.sub('[^a-z0-9]','',s.lower())
def inside(x,y,ring):
 c=False
 for (a,b),(d,e) in zip(ring,ring[1:]+ring[:1]):
  if (b>y)!=(e>y) and x<(d-a)*(y-b)/(e-b)+a: c=not c
 return c
parks=json.loads((RAW/'park-geometries.json').read_text())['features']
fountains=json.loads((RAW/'human-fountains.json').read_text())['features']
assert len(fountains)==94
byname={}
for f in fountains:
 assert f['attributes']['TYPE']=='Fountain Drinking'
 byname.setdefault(f['attributes']['FAC_NME'].strip(),[]).append(f)
assert len(byname)==38
places=[]
for name,fs in sorted(byname.items()):
 f=min(fs,key=lambda f:f['attributes']['OBJECTID']); g=f['geometry']
 exact=[p for p in parks if normalize(p['attributes']['ParkName'] or '')==normalize(name)]
 spatial=[p for p in parks if p['attributes']['ParkName'] and p.get('geometry') and any(inside(g['x'],g['y'],r) for r in p['geometry']['rings'])]
 candidates=exact or spatial
 assert len(candidates)==1,(name,[(p['attributes']['ParkName'],p['attributes']['OBJECTID']) for p in candidates])
 p=candidates[0]['attributes']; address=p['ParkAddress']; assert address
 point=dict(latitude=g['y'],longitude=g['x'],sourceUrl=CITY,precision='City GPS-mapped drinking fountain; park entrance may differ.')
 places.append(dict(id='community-city-'+str(p['OBJECTID']),name=p['ParkName'],aliases=[name] if name!=p['ParkName'] else [],address=address+', Las Vegas, NV',area='Las Vegas area',kind='park',officialCoolingStation=False,methods=['drinkingWater'],access='Outdoor drinking-water stop during posted park hours.',hours=None,phone=None,coordinates=point,sourceIds=['city-fountains','city-parks'],evidence=dict(parkFeatureId=p['OBJECTID'],fountainFeatureIds=sorted(f['attributes']['OBJECTID'] for f in fs),fountains=[dict(featureId=f['attributes']['OBJECTID'],latitude=f['geometry']['y'],longitude=f['geometry']['x']) for f in fs])))
selected={95:'Desert Breeze Park',98:'Exploration Peak Park',153:'Spring Valley Community Park',138:'Prosperity Park',93:'Davis Park',392:'Rainbow Family Park',112:'Inzalaco Family Park',139:'Red Ridge Park',440:'Charlie Frias Park',142:'Ridgebrook Park',96:'Duck Creek Park'}
def clean(s): return re.sub(r'\s+',' ',html.unescape(re.sub('<[^>]+>',' ',s))).strip()
for tid,name in selected.items():
 raw=(RAW/f'snhd-{tid}.html').read_text()
 assert 'title="Drinking Fountains"' in raw
 lat=float(re.search(r'class="latitude">([^<]+)',raw)[1]); lon=float(re.search(r'class="longitude">([^<]+)',raw)[1])
 addr=re.search(r'<th[^>]*>Address</th><td[^>]*>(.*?)</td>',raw,re.S)
 cross=re.search(r'<th[^>]*>Cross Streets</th><td[^>]*>(.*?)</td>',raw,re.S)
 if addr: address=clean(addr[1])
 else:
  matching=[p['attributes'] for p in parks if p['attributes']['ParkName']==name]
  address=(matching[0]['ParkAddress']+', Las Vegas, NV') if matching else clean(cross[1])+', Las Vegas, NV'
 url=f'https://app.gethealthyclarkcounty.org/neon2nature/traildetails.php?trail_id={tid}'
 sid=f'snhd-{tid}'; SOURCES.append(dict(id=sid,title=f'Southern Nevada Health District: {name}',url=url))
 places.append(dict(id=f'community-snhd-{tid}',name=name,aliases=[clean(re.search(r'Trail Name: (.*?)</',raw)[1])],address=address,area='Las Vegas area',kind='park',officialCoolingStation=False,methods=['drinkingWater'],access='Outdoor drinking-water stop during posted park hours.',hours=None,phone=None,coordinates=dict(latitude=lat,longitude=lon,sourceUrl=url,precision='Health District trailhead point; fountain is within the park.'),sourceIds=[sid]+(['city-parks'] if not addr and matching else []),evidence=dict(trailId=tid,amenityAsPublished='Drinking Fountains',coordinateRole='trailhead')))
mall=next(f for f in json.loads((RAW/'mall-photon.json').read_text())['features'] if f['properties'].get('osm_value')=='mall')
assert mall['properties']['osm_id']==38358961
lon,lat=mall['geometry']['coordinates']
places.append(dict(id='community-south-premium-outlets',name='Las Vegas South Premium Outlets',aliases=['Indoor mall','Food courts'],address='7400 Las Vegas Blvd S, Las Vegas, NV 89123',area='Las Vegas area',kind='mall',officialCoolingStation=False,methods=['airConditioning'],access='Indoor common areas during mall hours. Mall walkers welcome; follow the facility’s visitor access rules.',hours=None,phone='702-896-2247',coordinates=dict(latitude=lat,longitude=lon,sourceUrl='https://www.openstreetmap.org/way/38358961',precision='OpenStreetMap mall center via Photon; public entrance may differ.'),sourceIds=['mall-operator','mall-coordinate'],evidence=dict(operatorDescription='Climate controlled indoor mall',water='Water is sold; free drinking water not established.',osmType='way',osmId=38358961,coordinateRole='mall center')))
places.sort(key=lambda p:p['name'].lower())
assert len(places)==50 and len(set(p['id'] for p in places))==50
assert len(set(p['name'] for p in places))==50
for p in places:
 assert p['address'] and -115.5<p['coordinates']['longitude']<-114.9 and 35.8<p['coordinates']['latitude']<36.5
 assert not p['officialCoolingStation']
rawfiles=['fountain-layer.json','human-fountains.json','park-layer.json','park-features.json','park-geometries.json','mall-photon.json']+[f'snhd-{i}.html' for i in selected]
manifest=[]
for name in rawfiles:
 if RAW.resolve()!=DEST.resolve(): shutil.copyfile(RAW/name,DEST/name)
 manifest.append(dict(file=name,sha256=hashlib.sha256((DEST/name).read_bytes()).hexdigest()))
(DEST/'snapshot-manifest.json').write_text(json.dumps(dict(reviewedOn='2026-10-05',files=manifest),indent=2)+'\n')

for curated in ['indoor_destinations.json', 'additional_destinations.json']:
 indoor=json.loads((ROOT/'data/cooling_centers'/curated).read_text())
 places.extend(indoor['places'])
 SOURCES.extend(indoor['sources'])
places.sort(key=lambda p:p['name'].lower())
assert len({p['id'] for p in places})==len(places)
(ROOT/'data/cooling_centers/unofficial_directory.json').write_text(json.dumps(dict(schemaVersion=1,checkedOn='2026-10-05',placeCount=len(places),selection=f'49 sourced park water stops and {len(places)-49} indoor facilities/districts. Record evidence retains its own review date. Town Square and Downtown Summerlin have outdoor walkways; resorts cover permitted non-gaming visitor areas only. Not a complete inventory.',sources=SOURCES,places=places),indent=2,ensure_ascii=False)+'\n')
print('Built',len(places),'places:',len(byname),'city parks +',len(selected),'Health District parks + 1 indoor mall')
