'prepare pilot buildings'
import datetime as dt
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from prepare_osm_buildings import extract_buildings

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'data/osm/pilot/meadows-area.osm'
URL = 'https://api.openstreetmap.org/api/0.6/map?bbox=-115.299,36.185,-115.272,36.211'

def prepare():
    raw = SOURCE.read_bytes()
    root = ET.fromstring(raw)
    bounds = root.find('bounds').attrib
    buildings, skipped, relations, gaps = extract_buildings(root)

    tags = {'way/' + w.attrib['id']: {t.attrib['k']: t.attrib['v']
            for t in w.findall('tag')} for w in root.findall('way')}
    for b in buildings:
        b['tags'] = tags.get(b['osmId'], b['tags'])
        if b['heightSource'] == 'assumed':
            b['heightMeters'] = None
            b['heightConfidence'] = 'unknown'
            b['heightSource'] = 'unknown'
        if any(k in b['tags'] for k in ('min_height', 'building:min_level', 'building:part')):
            b['heightMeters'] = None
            b['heightSource'] = 'unsupported vertical geometry'
            b['heightConfidence'] = 'unknown'
    data = {
        'schemaVersion': 1, 'sourceUrl': URL,
        'retrievedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
        'sourceSha256': hashlib.sha256(raw).hexdigest(),
        'attribution': '© OpenStreetMap contributors',
        'licenseUrl': 'https://www.openstreetmap.org/copyright',
        'bounds': {k: float(bounds[v]) for k, v in
                   [('south','minlat'),('north','maxlat'),('west','minlon'),('east','maxlon')]},
        'buildings': buildings, 'coverageGaps': gaps,
        'skippedWays': skipped, 'skippedBuildingRelations': relations,
        'limitations': 'Mapped footprints only; completeness, trees, entrances and heights are not field verified.'
    }
    target = ROOT / 'data/buildings/pilot/buildings.json'
    target.write_text(json.dumps(data, separators=(',', ':')) + '\n')
    print(json.dumps({'buildings':len(buildings), 'explicitHeights':sum(b['heightSource']=='height' for b in buildings),
        'levelEstimates':sum(b['heightSource']=='building:levels' for b in buildings),
        'unknownHeights':sum(b['heightMeters'] is None for b in buildings), 'gaps':len(gaps)}))

if __name__ == '__main__': prepare()
