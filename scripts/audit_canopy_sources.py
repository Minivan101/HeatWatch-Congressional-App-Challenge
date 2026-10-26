'check the tree data'

import argparse, contextlib, datetime, gzip, json, math
from pathlib import Path
import numpy as np
import rasterio

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', required=True)
    ap.add_argument('--root', default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument('--cache', required=True)
    a = ap.parse_args()
    base = Path(a.root) / 'data/shade/las_vegas'
    cache = Path(a.cache)
    m = json.loads((base / 'manifest.json').read_text())
    b = m['bounds']
    rad = math.pi / 180
    R = 6378137
    (left, right) = (R * b['west'] * rad, R * b['east'] * rad)
    bottom = R * math.log(math.tan(math.pi / 4 + b['south'] * rad / 2))
    top = R * math.log(math.tan(math.pi / 4 + b['north'] * rad / 2))
    checked = 0
    mismatches = []
    known = 0
    unknown = 0
    offsets = [0, 32, 96, 160, 224, 288, 416, 511]
    with contextlib.ExitStack() as stack:
        rasters = [stack.enter_context(rasterio.open(p)) for p in sorted(cache.glob('*.tif'))]
        assert len(rasters) == 4, 'Expected the four original canopy source rasters'
        assert all((str(s.crs) == 'EPSG:3857' for s in rasters))
        source_info = [{'file': Path(s.name).name, 'crs': str(s.crs), 'nodata': s.nodata, 'dtype': s.dtypes[0], 'pixelSizeProjectedMeters': [s.transform.a, abs(s.transform.e)]} for s in rasters]
        for (key, t) in m['tiles'].items():
            (ix, iy) = map(int, key.split('_'))
            coords = []
            indices = []
            cells = gzip.decompress((base / t['canopy']).read_bytes())
            for row in offsets:
                for col in offsets:
                    coords.append((ix * 2560 + (col + 0.5) * 5, (iy + 1) * 2560 - (row + 0.5) * 5))
                    indices.append(row * 512 + col)
            expected = np.full(len(coords), 255, dtype=np.uint8)
            for s in rasters:
                samples = list(s.sample(coords, masked=True))
                for (j, ((x, y), v)) in enumerate(zip(coords, samples)):
                    if not (s.bounds.left <= x < s.bounds.right and s.bounds.bottom < y <= s.bounds.top):
                        continue
                    if not np.ma.is_masked(v[0]) and int(v[0]) != 255:
                        expected[j] = int(v[0])
            for (j, ((x, y), i)) in enumerate(zip(coords, indices)):
                if not (left <= x <= right and bottom <= y <= top):
                    expected[j] = 255
                checked += 1
                known += int(expected[j] != 255)
                unknown += int(expected[j] == 255)
                if cells[i] != int(expected[j]):
                    mismatches.append({'tile': key, 'row': i // 512, 'col': i % 512, 'packaged': cells[i], 'rawSource': int(expected[j])})
    report = {'checkedOn': datetime.datetime.now().astimezone().date().isoformat(), 'method': 'Independent direct source-raster lookup at 64 deterministic destination cell centers per tile, respecting original nodata and extraction bounds; no importer reproject function used.', 'samplesChecked': checked, 'knownSourceSamples': known, 'unknownOrOutsideSamples': unknown, 'mismatchCount': len(mismatches), 'mismatches': mismatches, 'sources': source_info, 'physicalAccuracyVerified': False}
    Path(a.output).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for (k, v) in report.items() if k not in ['mismatches', 'sources']}, indent=2))
    if mismatches:
        print('First mismatches:', mismatches[:8])
        raise SystemExit(1)
if __name__ == '__main__':
    main()
