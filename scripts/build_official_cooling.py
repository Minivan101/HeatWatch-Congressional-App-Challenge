'prepare cooling places'

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / 'data/cooling_centers/research'
GIS = 'https://maps.clarkcountynv.gov/arcgis/rest/services/GISMO/PointOfInterest/MapServer'
DAY = {'Mon': 1, 'Tue': 2, 'Tu': 2, 'Wed': 3, 'Thu': 4, 'Thurs': 4,
       'Fri': 5, 'Sat': 6, 'Sun': 7}
CONFLICTS = {
    'american-legion': ['English sources list 9am–9pm; Spanish August lists 8am–8pm. Current hours unresolved.'],
    'blue-diamond-library': ['Wednesday: English flyers 12pm–7pm; Spanish flyer 10am–7pm; county map 12pm–4pm. Current hours unresolved.'],
    'neighborhood-recreation-center': ['August lists Saturday 9am–2pm (English rendered line partly obscured). September and map omit Saturday; omission does not mean closed.'],
    'the-salvation-army': ['Map specifies pets on leash when active; flyers do not specify a pet policy.'],
    'whitney-recreation-center': ['Flyers specify carrier and/or leash; map omits a pet statement.'],
}

def read(name):
    return json.loads((RESEARCH / name).read_text())

def clean_address(lines):

    text = ' '.join(lines)
    for old, new in [('1 6A', '16A'), ('1 50', '150'), ('9 600', '9600'),
                     ('Lake M ead', 'Lake Mead'), ('P kwy.', 'Pkwy.')]:
        text = text.replace(old, new)
    return text

def schedule(lines):

    text = re.sub(r'\s*:\s*', ':', ' '.join(lines)).replace('–', '-')
    result = {str(i): None for i in range(1, 8)}
    if '24 hours daily' in text:
        return {str(i): [{'startMinute': 0, 'endMinute': 1440}] for i in range(1, 8)}
    if 'daily' in text:
        text = 'daily ' + text.replace('Hours:', '').replace('daily', '').strip()
    pattern = r'((?:(?:Mon|Tue|Tu|Wed|Thurs|Thu|Fri|Sat|Sun)(?:-|,\s*|\s*)?)+|daily)\s*:?\s*(\d{1,2}):(\d{2})(am|pm)\s*-\s*(\d{1,2}):(\d{2})(am|pm)'
    for match in re.finditer(pattern, text):
        days, h1, m1, a1, h2, m2, a2 = match.groups()
        if days == 'daily':
            indices = range(1, 8)
        else:
            indices = []
            for part in days.strip().split(','):
                labels = re.findall(r'Mon|Tue|Tu|Wed|Thurs|Thu|Fri|Sat|Sun', part)
                if '-' in part and len(labels) == 2:
                    indices.extend(range(DAY[labels[0]], DAY[labels[1]] + 1))
                else:
                    indices.extend(DAY[label] for label in labels)
        start = (int(h1) % 12 + (12 if a1 == 'pm' else 0)) * 60 + int(m1)
        end = (int(h2) % 12 + (12 if a2 == 'pm' else 0)) * 60 + int(m2)
        if not 0 <= start < end <= 1440:
            raise ValueError('Unsupported interval: ' + match.group())
        for day in indices:
            result[str(day)] = [{'startMinute': start, 'endMinute': end}]
    if 'Closed Weekends' in text:
        result['6'] = result['7'] = []
    return result if any(v is not None for v in result.values()) else None

def normal(text):
    return re.sub(r'[^a-z0-9]', '', text.lower())

def build():
    research = read('cooling-stations-research.json')
    map_data = read('county-map-stations.json')
    map_coordinates = read('county-map-coordinate-sources.json')
    facility_coordinates = read('facility-coordinate-sources.json')
    assert len(map_coordinates['records']) == 44
    assert hashlib.sha256((RESEARCH / map_coordinates['file']).read_bytes()).hexdigest() == map_coordinates['sha256']
    for item in facility_coordinates:
        assert hashlib.sha256((RESEARCH / item['file']).read_bytes()).hexdigest() == item['sha256']
    assert research['listingCount'] == 132 and map_data['stationCount'] == 44
    assert all(c['records'] == 44 and c['phonesMatchFullSourceText']
               and c['missingAddressRecords'] == 0 and c['missingEffectiveHours'] == 0
               for c in research['extractionChecks'])
    for source in research['sources']:
        assert hashlib.sha256((RESEARCH / source['file']).read_bytes()).hexdigest() == source['sha256']
    sources = research['sources'] + [{
        'id': 'county-resource-map', 'url': map_data['sourceUrl'],
        'retrievedOn': map_data['retrievedOn'], 'publicationDate': None,
        'hostingProvenance': 'County-embedded map; owner Clark County DES',
        'language': 'en', 'activationStart': None, 'activationEnd': None,
        'context': {k: v for k, v in map_data.items() if k != 'records'},
    }]
    features = []
    for file, layer in [('county-gis-libraries.geojson', 1), ('county-gis-centers.geojson', 6)]:
        snapshot = read(file)
        assert not snapshot.get('exceededTransferLimit')
        features.extend((feature, layer) for feature in snapshot['features'])
    stations = []
    for station in research['stations']:
        sid = station['stationId']
        flyers = [r.copy() for r in research['records'] if r['stationId'] == sid]
        panels = [r.copy() for r in map_data['records'] if r['stationId'] == sid]
        assert len(flyers) == 3 and len(panels) == 1
        first = next(r for r in flyers if r['sourceId'] == 'aug-en')
        address = clean_address(first['addressAndDirectionsLines'])
        for record in flyers:
            lines = [record['sharedHoursApplied']] if record['sharedHoursApplied'] else record['hoursLinesAsPrinted']
            record['weeklyHours'] = schedule(lines) if record['sourceId'] != 'aug-es' else None
            if record['sourceId'] != 'aug-es':
                assert record['weeklyHours'] is not None, sid
        for record in panels:
            record['weeklyHours'] = schedule(record['descriptionAsDisplayed'].splitlines())
        name = panels[0]['nameAsDisplayed']

        aliases = {'pearson-community-center': "Dr. William U. Pearson Recreation Center"}
        matched = []
        candidates = []
        for feature, layer in features:
            props = feature['properties']
            gis_name = props.get('Name', props.get('FAC_NAME'))
            gis_address = props.get('Address', props.get('FAC_ADD'))
            if normal(gis_name) not in {normal(name), normal(first['name']), normal(aliases.get(sid, ''))}:
                continue
            candidates.append({'layer': layer, 'objectId': props['OBJECTID'], 'name': gis_name, 'address': gis_address})

            expected = clean_address([first['addressAndDirectionsLines'][0]]).split(',')[0]
            a = re.findall(r'[a-z0-9]+', expected.lower())
            b = re.findall(r'[a-z0-9]+', gis_address.lower())
            suffixes = {'n', 's', 'e', 'w', 'north', 'south', 'east', 'west', 'st', 'street', 'rd', 'road', 'dr', 'drive', 'ave', 'avenue', 'blvd', 'boulevard', 'ln', 'lane', 'pkwy', 'parkway', 'hwy', 'highway', 'state'}
            a = [v for v in a if v not in suffixes]
            b = [v for v in b if v not in suffixes]
            if a != b:
                continue
            geometry = feature['geometry']
            if geometry['type'] == 'Point':
                longitude, latitude = geometry['coordinates'][:2]
                precision = 'County GIS facility point; entrance not verified'
            elif geometry['type'] == 'Polygon':
                points = [point for ring in geometry['coordinates'] for point in ring]
                longitude = (min(p[0] for p in points) + max(p[0] for p in points)) / 2
                latitude = (min(p[1] for p in points) + max(p[1] for p in points)) / 2
                precision = 'Approximate county facility polygon bounding-box center; entrance not verified'
            else:
                continue
            matched.append({'latitude': latitude, 'longitude': longitude, 'precision': precision,
                            'sourceUrl': f'{GIS}/{layer}', 'objectId': props['OBJECTID'],
                            'checkedOn': '2026-10-02', 'sourceName': gis_name, 'sourceAddress': gis_address})
        coordinates = matched[0] if len(matched) == 1 else None
        coordinate_status = 'address-matched' if coordinates else 'unresolved'
        if coordinates:
            coordinates['sourceKind'] = 'county-gis'
        facility = next((item for item in facility_coordinates if item['stationId'] == sid), None)
        if facility:
            data = facility['originalStructuredData']

            coordinates = {
                'latitude': data['geo']['latitude'], 'longitude': data['geo']['longitude'],
                'sourceKind': 'official-facility', 'sourceUrl': facility['sourceUrl'],
                'checkedOn': facility['retrievedOn'], 'objectId': None,
                'featureId': facility['sourceUrl'], 'sourceName': data['name'],
                'sourceAddress': data['address']['streetAddress'],
                'precision': 'Official facility-published GeoCoordinates; pedestrian entrance not verified',
            }
            coordinate_status = 'address-matched'
        if coordinates is None:
            pin = next(item for item in map_coordinates['records'] if item['stationId'] == sid)
            coordinates = {
                'latitude': pin['latitude'], 'longitude': pin['longitude'],
                'sourceKind': 'county-resource-map', 'sourceUrl': map_coordinates['sourceUrl'],
                'checkedOn': map_coordinates['retrievedOn'], 'objectId': None,
                'featureId': sid, 'sourceName': pin['name'], 'sourceAddress': None,
                'precision': 'County-authored cooling-map pin; street address and entrance not independently verified',
            }
            coordinate_status = 'source-matched'
        stations.append({
            'id': sid, 'name': name, 'address': address,
            'phone': first['phoneAsPrinted'], 'coordinates': coordinates,
            'coordinateReview': {'status': coordinate_status, 'candidates': candidates},
            'accessibility': None, 'waterAvailable': None, 'currentOpenStatus': 'unknown',
            'reviewNotes': CONFLICTS.get(sid, []), 'assertions': flyers + panels,
        })

    evidence = read('county-cooling-layer-evidence.json')
    for snapshot in evidence['snapshots']:
        assert hashlib.sha256((RESEARCH / snapshot['file']).read_bytes()).hexdigest() == snapshot['sha256']
    layer = json.loads((RESEARCH / evidence['recordsFile']).read_text())
    assert not layer.get('exceededTransferLimit') and len(layer['features']) == 45
    ids = json.loads((RESEARCH / 'sources/qr-county-layer-ids.json').read_text())['objectIds']
    assert sorted(ids) == sorted(f['properties']['OBJECTID'] for f in layer['features'])
    aliases = {
        'Downtown Senior Center (Age 50+)': 'downtown-senior-center',
        'The Salvation Army Family Services Center': 'the-salvation-army-family-services-center',
        'Mt. Charleston Library': 'mt-charleston-library',
        'Mesquite Library Campus': 'mesquite-library-campus',
    }
    sources.append({
        'id': 'county-cooling-gis', 'url': evidence['sourceUrl'],
        'retrievedOn': evidence['retrievedOn'], 'publicationDate': None,
        'hostingProvenance': evidence['provenance'], 'language': 'en',
        'activationStart': None, 'activationEnd': None,
    })
    seen = set()
    for feature in layer['features']:
        props = feature['properties']
        sid = aliases.get(props['Name'], re.sub(r'[^a-z0-9]+', '-', props['Name'].lower()).strip('-'))
        assert sid not in seen
        seen.add(sid)
        station = next((s for s in stations if s['id'] == sid), None)
        is_new = station is None
        if is_new:
            assert sid == 'meadows-library'
            station = {'id': sid, 'name': props['Name'],
                       'address': f"{props['Address']}, {props['City']}, {props['State']} {props['Zip']}",
                       'phone': props['Phone'], 'coordinates': None,
                       'coordinateReview': {'status': 'unresolved', 'candidates': []},
                       'accessibility': None, 'waterAvailable': None,
                       'currentOpenStatus': 'unknown', 'assertions': [],
                       'reviewNotes': ['Listed only in the reviewed county cooling GIS layer; activation dates not supplied.']}
            stations.append(station)
        station['assertions'].append({
            'stationId': sid, 'sourceId': 'county-cooling-gis',
            'rawText': json.dumps(props, ensure_ascii=False, indent=2),
            'originalFeature': feature, 'weeklyHours': None,
            'activationStart': None, 'activationEnd': None, 'currentOpenStatus': 'unknown',
        })
        station['reviewNotes'].append('The undated county cooling GIS listing is preserved separately. Its schedules do not confirm current cooling availability.')
        if not is_new and normal(station['phone']) != normal(props['Phone']):
            station['reviewNotes'].append(f"Phone conflict: flyers list {station['phone']}; county cooling GIS lists {props['Phone']}. Neither is treated as a live confirmation.")
        if sid in {'american-legion', 'blue-diamond-library'}:
            station['reviewNotes'].append('The county cooling GIS schedule also differs from other reviewed listings; read the source reports and confirm with the facility.')

        if is_new or station['coordinateReview']['status'] == 'source-matched':
            lon, lat = feature['geometry']['coordinates']
            assert feature['geometry']['type'] == 'Point'
            if not is_new:
                station['coordinateReview']['previousLocation'] = station['coordinates']
            station['coordinates'] = {
                'latitude': lat, 'longitude': lon, 'sourceKind': 'county-gis',
                'sourceUrl': evidence['sourceUrl'], 'objectId': props['OBJECTID'],
                'checkedOn': evidence['retrievedOn'], 'sourceName': props['Name'],
                'sourceAddress': props['Address'],
                'precision': 'County cooling GIS point with reviewed matching street address; pedestrian entrance not verified',
            }
            station['coordinateReview']['status'] = 'address-matched'
    assert len(stations) == 45 and all(s['id'] in seen for s in stations)
    for item in read('additional-address-evidence.json'):
        assert hashlib.sha256((RESEARCH / item['file']).read_bytes()).hexdigest() == item['sha256']
        station = next(s for s in stations if s['id'] == item['stationId'])
        station['addressEvidence'] = [item]
        if item.get('phoneAsPublished'):
            if normal(station['phone']) != normal(item['phoneAsPublished']):
                station['reviewNotes'].append(f"Contact conflict: flyers/GIS list {station['phone']}; the operator district directory and post website publish {item['phoneAsPublished']}. Contact button uses the operator-published number; availability remains unconfirmed.")
            station['phone'] = item['phoneAsPublished']
            station['phoneProvenance'] = {'sourceUrl': item['sourceUrl'], 'checkedOn': item['retrievedOn'], 'scope': 'Operator-published phone; not a successful call or availability confirmation.'}
    qr_links = read('qr-link-evidence.json')
    for qr in qr_links:
        assert qr['visuallyReviewed'] and hashlib.sha256((RESEARCH / qr['sourceFile']).read_bytes()).hexdigest() == qr['sourceSha256']
    for source in sources:
        source['qrLinks'] = [q for q in qr_links if q['sourceId'] == source['id']]
    result = {
        'schemaVersion': 1, 'revision': 1, 'datasetId': 'clark-county-reviewed-2026-10-02',
        'checkedOn': '2026-10-02', 'timeZoneId': 'America/Los_Angeles',
        'coverage': research['coverage'], 'stationCount': len(stations), 'assertionCount': sum(len(s['assertions']) for s in stations),
        'sources': sources, 'extractionChecks': research['extractionChecks'],
        'coordinateSources': [{
            'file': file, 'sourceUrl': f'{GIS}/{layer}/query?where=1%3D1&outFields=*&outSR=4326&f=geojson',
            'retrievedOn': '2026-10-02', 'coordinateSystem': 'WGS84 (EPSG:4326)',
            'sha256': hashlib.sha256((RESEARCH / file).read_bytes()).hexdigest(),
            'featurePublicationDate': None,
        } for file, layer in [('county-gis-libraries.geojson', 1), ('county-gis-centers.geojson', 6)]] + [{
            **{k: v for k, v in item.items() if k not in ['records', 'originalStructuredData']},
            'coordinateSystem': 'WGS84 (EPSG:4326)',
        } for item in [map_coordinates] + facility_coordinates] + [{
            'file': evidence['recordsFile'], 'sourceUrl': evidence['queryUrl'],
            'retrievedOn': evidence['retrievedOn'], 'coordinateSystem': 'WGS84 (EPSG:4326)',
            'sha256': next(item['sha256'] for item in evidence['snapshots'] if item['file'] == evidence['recordsFile']), 'featurePublicationDate': None,
        }],
        'stations': sorted(stations, key=lambda s: s['name']),
        'review': {'currentActivationVerified': False,
                   'coordinateMatches': sum(s['coordinates'] is not None for s in stations),
                   'addressMatches': sum(s['coordinateReview']['status'] == 'address-matched' for s in stations),
                   'countyMapPins': sum(s['coordinateReview']['status'] == 'source-matched' for s in stations),
                   'limitations': ['Not a complete historical archive.', 'No facility calls or site visits performed.',
                                  'Four QR codes decoded and destinations checked; redirected contents may change.', 'Unlisted days and pet rules remain unknown.',
                                  'GIS address mismatches are excluded; facility points or county map pins are attributed separately. No verified entrances.']},
    }

    update = read('reviewed-source-update-2026-10-11.json')
    for item in update.get('supportingEvidence', []):
        assert hashlib.sha256((RESEARCH / item['file']).read_bytes()).hexdigest() == item['sha256']
    for source in update['sources']:
        assert hashlib.sha256((RESEARCH / source['file']).read_bytes()).hexdigest() == source['sha256']
        result['sources'].append(source)
    by_id = {station['id']: station for station in result['stations']}
    for record in update['records']:
        by_id[record['stationId']]['assertions'].append(record)
    for station_id, notes in update['reviewNotes'].items():
        by_id[station_id]['reviewNotes'].extend(notes)
    result['extractionChecks'].extend(update['extractionChecks'])
    result['checkedOn'] = update['reviewedOn']
    result['datasetId'] = 'clark-county-reviewed-' + update['reviewedOn']
    result['coverage'] = 'All 44 entries in each of five reviewed county flyers plus county map/GIS assertions; 45 unique saved locations. Not a current-open inventory.'
    result['assertionCount'] = sum(len(s['assertions']) for s in result['stations'])
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / 'data/cooling_centers/official_directory.candidate.json')
    parser.add_argument('--revision', type=int, default=1)
    args = parser.parse_args()
    result = build()
    if args.revision < 1:
        parser.error('revision must be positive')
    result['revision'] = args.revision
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f"Staged {result['stationCount']} stations / {result['assertionCount']} assertions; {result['review']['coordinateMatches']} sourced points ({result['review']['addressMatches']} address matches, {result['review']['countyMapPins']} county map pins). Validate before installing.")
