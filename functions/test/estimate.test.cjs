const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {estimateShadeRoutes} = require('../lib/shade/estimate.js');
const {routes, buildEstimate} = require('../scripts/build_shade_demo.cjs');
const {expandedRouteBounds, loadPreparedBuildings} =
  require('../lib/shade/prepared_buildings.js');
const manifest = path.resolve(
  __dirname, '../../data/buildings/demo_las_vegas/manifest.json');

const realBuildings = () => loadPreparedBuildings(
  manifest, expandedRouteBounds(routes));

test('real saved OSM buildings produce ranked sample estimates', async () => {
  const buildings = await realBuildings();
  const result = estimateShadeRoutes(
    routes, buildings, new Date('2026-06-21T16:00:00Z'), -7 * 3600,
  );
  assert.equal(result.routes.length, 3);
  assert.equal(result.choices.fastest, 'direct');
  assert.equal(result.choices.balanced, 'north');
  assert.equal(result.choices.mostShade, 'north');
  assert.ok(result.routes[1].shadeFraction > result.routes[0].shadeFraction);
  assert.ok(result.routes.every((route) => route.shadeFraction >= 0 &&
    route.shadeFraction <= 1));
  assert.ok(result.routes.every((route) =>
    route.daylightDistanceMeters > 0 && route.sampleCount > 0));
});

test('nighttime routes return fastest only without a false shade percent', async () => {
  const buildings = await realBuildings();
  const result = estimateShadeRoutes(
    routes, buildings, new Date('2026-06-21T07:00:00Z'), -7 * 3600,
  );
  assert.equal(result.choices.fastest, 'direct');
  assert.equal(result.choices.balanced, null);
  assert.equal(result.choices.mostShade, null);
  assert.ok(result.routes.every((route) =>
    route.shadeFraction === null && route.daylightDistanceMeters === 0));
});

test('changing departure time changes modeled building shade', async () => {
  const buildings = await realBuildings();
  const morning = estimateShadeRoutes(
    routes, buildings, new Date('2026-06-21T16:00:00Z'), -7 * 3600,
  );
  const midday = estimateShadeRoutes(
    routes, buildings, new Date('2026-06-21T20:00:00Z'), -7 * 3600,
  );
  assert.notDeepEqual(morning.routes.map((r) => r.shadeFraction),
    midday.routes.map((r) => r.shadeFraction));
});

test('spatial index preserves shade estimates and route choices', async () => {
  const buildings = await realBuildings();
  for (const instant of ['2026-06-21T16:00:00Z',
    '2026-06-21T20:00:00Z', '2026-06-22T00:00:00Z',
    '2026-06-21T07:00:00Z']) {
    const args = [routes, buildings, new Date(instant), -7 * 3600];
    assert.deepEqual(estimateShadeRoutes(...args, true),
      estimateShadeRoutes(...args, false));
  }
});

test('simulator preview asset matches the real-building model output', async () => {
  const asset = JSON.parse(fs.readFileSync(path.resolve(
    __dirname, '../../assets/shade_demo.json'), 'utf8'));
  const result = await buildEstimate();
  assert.deepEqual(asset.routes, result.routes);
  assert.deepEqual(asset.choices, result.choices);
  assert.equal(asset.buildingCount, result.buildingCount);
  assert.equal(asset.source, 'OpenStreetMap building footprints');
  assert.equal(asset.sampleOnly, true);
});
