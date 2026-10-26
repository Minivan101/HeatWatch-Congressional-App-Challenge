'check shade files'

import argparse, collections, datetime, gzip, hashlib, json, math, statistics
from pathlib import Path

def fingerprint(rings):
    return hashlib.sha256(json.dumps(rings, separators=(',', ':')).encode()).digest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument('--cache', required=True)
    ap.add_argument('--output', required=True)
    args = ap.parse_args()
    root = Path(args.root)
    base = root / 'data/shade/las_vegas'
    cache = Path(args.cache)
    m = json.loads((base / 'manifest.json').read_text())
    records = {}
    heights = []
    confidence = collections.Counter()
    canopy = collections.Counter()
    checked = 0
    for (key, t) in m['tiles'].items():
        for (filefield, hashfield) in [('buildings', 'buildingSha256'), ('canopy', 'canopySha256')]:
            raw = (base / t[filefield]).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == t[hashfield], key
            checked += 1
        for (h, rings, c) in json.loads(gzip.decompress((base / t['buildings']).read_bytes())):
            f = fingerprint(rings)
            if f in records:
                assert records[f] == (h, c), 'Inconsistent cross-tile duplicate'
                continue
            assert rings and all((len(r) >= 3 for r in rings))
            assert all((math.isfinite(x) and math.isfinite(y) and (abs(y) < 70) and (abs(x) <= 180) for ring in rings for (x, y) in ring))
            assert h is None or (math.isfinite(h) and 0 < h <= 500)
            records[f] = (h, c)
            if h is not None:
                heights.append(h)
            confidence['unknown' if c < 0 else 'below_0.5' if c < 0.5 else '0.5_to_0.8' if c < 0.8 else 'at_least_0.8'] += 1
        cells = gzip.decompress((base / t['canopy']).read_bytes())
        assert len(cells) == 512 * 512
        canopy.update(cells)
    assert len(records) == m['buildingCounts']['footprints']
    assert len(heights) == m['buildingCounts']['heights']
    assert sum(canopy.values()) - canopy[255] == m['canopyValidCells']
    assert sum((v for (k, v) in canopy.items() if 2 <= k < 255)) == m['canopyCellsAtLeast2m']
    rawhash = []
    for source in m['sources']:
        if source['kind'] == 'Microsoft buildings':
            q = source['url'].split('quadkey=')[1].split('/')[0]
            p = cache / (q + '.geojsonl.gz')
        else:
            stem = source['url'].split('/')[-1]
            p = cache / stem.replace('.geojson', '.metadata.geojson')
        assert p.exists(), p
        assert hashlib.sha256(p.read_bytes()).hexdigest() == source['sha256'], p
        rawhash.append({'kind': source['kind'], 'file': p.name, 'sha256Matches': True})
    matched = set()
    raw_mismatches = []
    for p in sorted(cache.glob('*.geojsonl.gz')):
        with gzip.open(p, 'rt') as f:
            for line in f:
                d = json.loads(line)
                g = d['geometry']
                if g['type'] != 'Polygon':
                    continue
                ring = g['coordinates'][0]
                b = m['bounds']
                if max((x[0] for x in ring)) < b['west'] or min((x[0] for x in ring)) > b['east'] or max((x[1] for x in ring)) < b['south'] or (min((x[1] for x in ring)) > b['north']):
                    continue
                rings = [[[round(p[0], 7), round(p[1], 7)] for p in r[:-1]] for r in g['coordinates']]
                key = fingerprint(rings)
                if key not in records:
                    continue
                h = d['properties'].get('height', -1)
                h = round(h, 2) if isinstance(h, (int, float)) and math.isfinite(h) and (0 < h <= 500) else None
                h = h if h and h > 0 else None
                c = d['properties'].get('confidence', -1)
                if records[key] != (h, c):
                    raw_mismatches.append(key.hex())
                matched.add(key)
    assert not raw_mismatches
    assert len(matched) == len(records), (len(matched), len(records))
    heights.sort()
    report = {'checkedOn': datetime.datetime.now().astimezone().date().isoformat(), 'scope': 'Packaged-file integrity and source-to-package values, not measured shade accuracy', 'packagedFilesChecked': checked, 'sourceHashesChecked': rawhash, 'uniqueFootprints': len(records), 'sourceFootprintHeightConfidenceMatches': len(matched), 'heightsAvailable': len(heights), 'unknownHeights': len(records) - len(heights), 'heightStatisticsMeters': {'minimum': heights[0], 'median': statistics.median(heights), 'p95': heights[int(0.95 * (len(heights) - 1))], 'maximum': heights[-1]}, 'footprintDetectionConfidenceCounts': dict(confidence), 'canopyCells': {'total': sum(canopy.values()), 'unknownOrOutside': canopy[255], 'validZero': canopy[0], 'validAtLeast2m': sum((v for (k, v) in canopy.items() if 2 <= k < 255))}, 'canopyObservationDatesIntersectingExtract': m['canopyObservationDatesIntersectingExtract'], 'coverageGaps': m['coverageGaps'], 'groundAccuracyVerified': False, 'remaining': 'Field observations or independent ground-normalized lidar are required; confidence is footprint detection, not height certainty.'}
    Path(args.output).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for (k, v) in report.items() if k not in ['sourceHashesChecked', 'canopyObservationDatesIntersectingExtract', 'coverageGaps']}, indent=2))
if __name__ == '__main__':
    main()
