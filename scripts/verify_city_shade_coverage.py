'check shade coverage'

import argparse
import datetime
import gzip
import hashlib
import json
import math
from pathlib import Path

def audit(root, boundary_path):
    base = root / 'data/shade/las_vegas'
    manifest = json.loads((base / 'manifest.json').read_text())
    boundary = json.loads(boundary_path.read_text())
    bounds = manifest['bounds']
    margin = manifest['shadowLimitMeters'] / 111195
    envelopes = []
    for source in boundary['sources']:
        extent = source['extent']
        assert extent['spatialReference']['wkid'] == 4326
        lon_margin = margin / math.cos(math.radians(extent['ymax']))
        contains = (bounds['west'] <= extent['xmin'] - lon_margin and
                    bounds['east'] >= extent['xmax'] + lon_margin and
                    bounds['south'] <= extent['ymin'] - margin and
                    bounds['north'] >= extent['ymax'] + margin)
        assert contains, 'City boundary requires additional shade tiles'
        envelopes.append({'name': source['name'], 'url': source['url'],
                          'withinDatasetWith250mBuffer': contains})
    seen = set()
    heights = unknown_heights = valid_cells = tree_cells = checked = 0
    missing_inside = inside_cells = 0
    radius = 6378137
    def xy(lon, lat):
        return (radius * math.radians(lon), radius * math.log(
            math.tan(math.pi / 4 + math.radians(lat) / 2)))
    west, south = xy(bounds['west'], bounds['south'])
    east, north = xy(bounds['east'], bounds['north'])
    for key, tile in manifest['tiles'].items():
        for name, checksum in [('buildings', 'buildingSha256'),
                               ('canopy', 'canopySha256')]:
            packed = (base / tile[name]).read_bytes()
            assert hashlib.sha256(packed).hexdigest() == tile[checksum], key
            checked += 1
        records = json.loads(gzip.decompress((base / tile['buildings']).read_bytes()))
        for height, rings, confidence in records:
            assert rings and all(len(ring) >= 3 for ring in rings)
            assert all(math.isfinite(x) and math.isfinite(y)
                       for ring in rings for x, y in ring)
            assert height is None or math.isfinite(height) and 0 < height <= 500
            identifier = hashlib.sha256(json.dumps(rings, separators=(',', ':')).encode()).digest()
            if identifier in seen:
                continue
            seen.add(identifier)
            heights += height is not None
            unknown_heights += height is None
        cells = gzip.decompress((base / tile['canopy']).read_bytes())
        assert len(cells) == 512 * 512
        valid_cells += len(cells) - cells.count(255)
        tree_cells += sum(cells.count(h) for h in range(2, 255))
        col0 = max(0, math.ceil((west - tile['x']) / 5 - .5))
        col1 = min(512, math.floor((east - tile['x']) / 5 - .5) + 1)
        for row in range(512):
            y = tile['y'] - (row + .5) * 5
            if south <= y <= north and col1 > col0:
                strip = cells[row * 512 + col0:row * 512 + col1]
                inside_cells += len(strip)
                missing_inside += strip.count(255)
    counts = manifest['buildingCounts']
    assert len(seen) == counts['footprints']
    assert heights == counts['heights'] and unknown_heights == counts['missingHeights']
    assert valid_cells == manifest['canopyValidCells']
    assert tree_cells == manifest['canopyCellsAtLeast2m']
    return {'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'datasetRetrievedAt': manifest['retrievedAt'],
            'boundaryRetrievedAt': boundary['retrievedAt'],
            'boundaryChecks': envelopes, 'bounds': bounds,
            'tiles': len(manifest['tiles']), 'filesHashVerified': checked,
            'uniqueBuildings': len(seen), 'estimatedHeights': heights,
            'unknownBuildingHeights': unknown_heights,
            'canopyValidCells': valid_cells, 'canopyTreeCells': tree_cells,
            'canopyCellsInsideExtraction': inside_cells,
            'canopyMissingCellsInsideExtraction': missing_inside,
            'invalidSourcePolygonGaps': manifest['coverageGaps'],
            'physicalShadeAccuracyVerified': False,
            'scope': 'Packaged file integrity and official city envelope coverage; '
                     'missing heights/canopy stay unknown. Does not establish '
                     'that every street/entrance is mapped or safely walkable.'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--boundary', type=Path,
                        default=Path('docs/research/las-vegas-boundary-2026-10-10.json'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    boundary = args.boundary if args.boundary.is_absolute() else args.root / args.boundary
    report = audit(args.root, boundary)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ['boundaryChecks', 'invalidSourcePolygonGaps']}, indent=2))

if __name__ == '__main__':
    main()
