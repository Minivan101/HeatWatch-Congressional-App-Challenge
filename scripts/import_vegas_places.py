'prepare place data'
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path

BOUNDS = [36.04, -115.50, 36.4015, -115.04]
QUERY = '[out:json][timeout:90][maxsize:67108864];nwr["name"][~"^(amenity|shop|tourism|leisure|office|healthcare|public_transport)$"~"."](36.04,-115.50,36.4015,-115.04);out center tags;'

def convert(data):
    if data.get('remark') or not isinstance(data.get('elements'), list):
        raise ValueError('Incomplete or malformed Overpass snapshot')
    result, seen, skipped = [], set(), Counter()
    for item in data['elements']:
        tags = item.get('tags', {})
        name = tags.get('name:en') or tags.get('name')
        if not isinstance(name, str) or not name.strip():
            skipped['missing_name'] += 1; continue
        if any(tags.get(k) == 'yes' for k in ('disused', 'abandoned', 'demolished')):
            skipped['inactive'] += 1; continue
        center = item if item.get('type') == 'node' else item.get('center', {})
        lat, lon = center.get('lat'), center.get('lon')
        if (isinstance(lat, bool) or isinstance(lon, bool) or
                not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)) or
                not math.isfinite(lat) or not math.isfinite(lon) or
                not BOUNDS[0] <= lat <= BOUNDS[2] or not BOUNDS[1] <= lon <= BOUNDS[3]):
            skipped['invalid_or_outside'] += 1; continue
        if item.get('type') not in ('node', 'way', 'relation') or not isinstance(item.get('id'), int):
            skipped['invalid_identity'] += 1; continue
        identity = f"{item['type']}/{item['id']}"
        if identity in seen:
            skipped['duplicate_id'] += 1; continue
        seen.add(identity)
        address = ' '.join(str(tags[k]).strip() for k in
            ('addr:housenumber', 'addr:street', 'addr:city', 'addr:postcode') if tags.get(k))
        aliases = sorted({str(tags[k]).strip() for k in
            ('name', 'alt_name', 'short_name', 'official_name', 'brand', 'operator')
            if tags.get(k) and tags[k] != name})
        category = next((f'{k}:{tags[k]}' for k in
            ('amenity', 'shop', 'tourism', 'leisure', 'office', 'healthcare', 'public_transport') if tags.get(k)), '')
        result.append({'id': identity, 'name': name.strip(), 'address': address,
            'latitude': lat, 'longitude': lon, 'aliases': aliases, 'category': category,
            'precision': 'mapped point' if item['type'] == 'node' else 'mapped feature center',
            'access': tags.get('access'), 'sourceUrl': 'https://www.openstreetmap.org/' + identity})
    result.sort(key=lambda p: (p['name'].casefold(), p['id']))
    return result, dict(skipped)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--output', type=Path, default=Path('data/places/las_vegas.json'))
    args = parser.parse_args()
    raw = args.snapshot.read_bytes(); data = json.loads(raw)
    places, skipped = convert(data)
    payload = {'version': 1, 'source': 'OpenStreetMap via Overpass',
        'sourceUrl': 'https://overpass-api.de/api/interpreter',
        'license': 'ODbL-1.0', 'attribution': '© OpenStreetMap contributors',
        'licenseUrl': 'https://www.openstreetmap.org/copyright',
        'retrievedAt': datetime.now(timezone.utc).isoformat(),
        'sourceDataAt': data.get('osm3s', {}).get('timestamp_osm_base'),
        'snapshotSha256': hashlib.sha256(raw).hexdigest(), 'query': QUERY,
        'bounds': BOUNDS, 'rawElements': len(data['elements']), 'skipped': skipped,
        'count': len(places), 'places': places,
        'limits': 'Published map records; not current-operation, public-access, entrance or sidewalk verification. Centers are not asserted entrances.'}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, separators=(',', ':')) + '\n')
    print(json.dumps({'places': len(places), 'skipped': skipped, 'bytes': args.output.stat().st_size}))

if __name__ == '__main__': main()
