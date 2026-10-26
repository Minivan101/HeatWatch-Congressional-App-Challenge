'solar position checks'

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import math
from pathlib import Path

SOURCE_URL = 'https://raw.githubusercontent.com/pvlib/pvlib-python/v0.15.0/pvlib/spa.py'
SOURCE_SHA256 = 'b7858858d9dceac4c9ad98a0a0f56cefba9e2bf972c63e5c1c243e74888e3dfc'
POINTS = [(36.19531, -115.28587), (36.04, -115.50), (36.04, -115.04),
          (36.40, -115.50), (36.40, -115.04)]
UTC = dt.timezone.utc

def build_reference(module_path):

    actual_hash = hashlib.sha256(module_path.read_bytes()).hexdigest()
    if actual_hash != SOURCE_SHA256:
        raise ValueError('SPA source hash does not match the reviewed version.')
    import numpy as np
    spec = importlib.util.spec_from_file_location('reference_spa', module_path)
    spa = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(spa)

    benchmark_at = dt.datetime(2003, 10, 17, 19, 30, 30, tzinfo=UTC)
    benchmark = spa.solar_position(np.array([benchmark_at.timestamp()]),
                                  39.742476, -105.1786, 1830.14, 820, 11,
                                  67, 0.5667, numthreads=1)
    if not (math.isclose(float(benchmark[3][0]), 39.872046, abs_tol=1e-6)
            and math.isclose(float(benchmark[4][0]), 194.340241, abs_tol=1e-6)):
        raise ValueError('Independent SPA benchmark failed.')

    def positions(dates, lat, lon):
        return spa.solar_position(np.array([d.timestamp() for d in dates]),
                                  lat, lon, 0, 0, 12, 67, 0.5667, numthreads=1)

    cases = []
    boundaries = [
        '2024-02-29T23:59:59Z', '2024-03-01T00:00:00Z',
        '2026-01-01T00:00:00Z', '2026-12-31T23:59:59Z',
        '2027-01-01T00:00:00Z', '2026-03-08T09:59:59Z',
        '2026-03-08T10:00:00Z', '2026-11-01T08:59:59Z',
        '2026-11-01T09:00:00Z', '2026-10-07T19:00:00Z',
    ]
    for lat, lon in POINTS:
        dates = [dt.datetime(year, month, 15, hour, tzinfo=UTC)
                 for year in (2024, 2026) for month in range(1, 13)
                 for hour in range(24)]
        dates.extend(dt.datetime.fromisoformat(s.replace('Z', '+00:00'))
                     for s in boundaries)

        for year in (2024, 2026):
            for month in (3, 6, 9, 12):
                day = dt.datetime(year, month, 15, tzinfo=UTC)
                hourly = [day + dt.timedelta(hours=h) for h in range(25)]
                elev = positions(hourly, lat, lon)[3]
                for index in range(24):
                    if (elev[index] > 0) == (elev[index + 1] > 0):
                        continue
                    left, right = hourly[index], hourly[index + 1]
                    left_positive = elev[index] > 0
                    while (right - left).total_seconds() > 1:
                        midpoint = left + (right - left) / 2
                        positive = positions([midpoint], lat, lon)[3][0] > 0
                        if positive == left_positive:
                            left = midpoint
                        else:
                            right = midpoint
                    crossing = (left + (right - left) / 2).replace(microsecond=0)
                    dates.extend(crossing + dt.timedelta(minutes=m)
                                 for m in (-2, 0, 2))
        dates = sorted(set(dates))
        values = positions(dates, lat, lon)
        for index, at in enumerate(dates):
            cases.append([at.isoformat().replace('+00:00', 'Z'), lat, lon,
                          float(values[3][index]), float(values[4][index])])
    return {
        'schemaVersion': 1,
        'sourceUrl': SOURCE_URL,
        'sourceSha256': SOURCE_SHA256,
        'reference': 'pvlib 0.15.0 NREL SPA; geometric topocentric elevation; azimuth clockwise from north',
        'benchmarkSource': 'https://github.com/pvlib/pvlib-python/blob/v0.15.0/tests/test_spa.py',
        'referenceParameters': {'altitudeMeters': 0, 'pressureMillibars': 0,
                                'temperatureCelsius': 12, 'deltaTSeconds': 67,
                                'atmosphericRefractionDegrees': 0.5667},
        'scope': 'Five public planning-area points; monthly hourly 2024/2026, UTC boundaries and geometric horizon crossings. Numerical reference, not observed shade.',
        'columns': ['utc', 'latitude', 'longitude', 'elevationDegrees', 'azimuthDegrees'],
        'cases': cases,
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spa-module', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = build_reference(args.spa_module)

    rows = result.pop('cases')
    header = json.dumps(result, indent=2)
    body = ',\n'.join('    ' + json.dumps(row) for row in rows)
    args.output.write_text(header[:-2] + ',\n  "cases": [\n' + body + '\n  ]\n}\n')
    print(f'Wrote {len(rows)} independent checkpoints to {args.output}')

if __name__ == '__main__':
    main()
