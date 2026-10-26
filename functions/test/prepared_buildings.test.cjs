const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs/promises');
const os = require('node:os');

const {expandedRouteBounds, loadPreparedBuildings} =
  require('../lib/shade/prepared_buildings.js');
const {routes} = require('../scripts/build_shade_demo.cjs');
const manifest = path.resolve(
  __dirname, '../../data/buildings/demo_las_vegas/manifest.json');

test('local building tiles load unique real OSM footprints', async () => {
  const saved = JSON.parse(await fs.readFile(manifest, 'utf8'));
  const buildings = await loadPreparedBuildings(manifest, saved.coverageBounds);
  assert.equal(buildings.length, saved.buildingCount);
  assert.ok(buildings.every((b) => b.footprint.length >= 3 &&
    b.footprint.every((p) => p.latitude > 36 && p.longitude < -115)));
  assert.ok(saved.heightConfidenceCounts.low > 0);
});

test('local building loader refuses an uncovered route area', async () => {
  await assert.rejects(loadPreparedBuildings(manifest, {
    south: 36.18, west: -115.29,
    north: 36.192, east: -115.281,
  }), RangeError);
});

test('sample route bounds include the modeled 250 m shadow reach', async () => {
  const bounds = expandedRouteBounds(routes);
  assert.ok(bounds.west < -115.2873);
  assert.ok(bounds.east > -115.2811);
  const buildings = await loadPreparedBuildings(manifest, bounds);
  assert.ok(buildings.length > 1);
});

test('incomplete OSM shapes block estimates only where their bounds meet',
  async () => {
    const original = JSON.parse(await fs.readFile(manifest, 'utf8'));
    const temp = await fs.mkdtemp(path.join(os.tmpdir(), 'heatwatch-gaps-'));
    try {
      const copy = path.join(temp, 'manifest.json');
      await fs.writeFile(copy, JSON.stringify({...original,
        coverageGaps: [{reason: 'incomplete building relation', bounds: {
          south: 36.19, north: 36.1901,
          west: -115.284, east: -115.2839,
        }}], tiles: []}));
      await assert.rejects(loadPreparedBuildings(copy, {
        south: 36.1899, north: 36.1902,
        west: -115.2841, east: -115.2838,
      }), /incomplete shapes/);
      const away = await loadPreparedBuildings(copy, {
        south: 36.188, north: 36.1881,
        west: -115.286, east: -115.2859,
      });
      assert.deepEqual(away, []);
    } finally {
      await fs.rm(temp, {recursive: true, force: true});
    }
  });
