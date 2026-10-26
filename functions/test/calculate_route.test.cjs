const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const {calculateShadeRoute} = require('../lib/shade/calculate_route.js');
const {routes} = require('../scripts/build_shade_demo.cjs');
const timeZone = require('./fixtures/timezone_response.json');

const manifest = path.resolve(
  __dirname, '../../data/buildings/demo_las_vegas/manifest.json');
const request = {
  origin: {latitude: 36.18998, longitude: -115.28460},
  destination: {latitude: 36.18998, longitude: -115.28380},
  departureTime: new Date('2026-06-21T16:00:00Z'),
};
const returnedRoutes = routes.map((route, index) => ({
  duration: `${route.durationSeconds}s`,
  distanceMeters: 127 + index * 15,
  polyline: {encodedPolyline: route.encodedPolyline},
}));

test('local providers run the complete route-to-shade pipeline', async () => {
  const result = await calculateShadeRoute(request, {
    getWalkingRoutes: async () => ({routes: returnedRoutes}),
    getTimeZone: async () => timeZone,
  }, manifest);
  assert.equal(result.routes.length, 3);
  assert.equal(result.choices.fastest, 'route-1');
  assert.equal(result.choices.mostShade, 'route-2');
  assert.ok(result.buildingCount > 0);
  assert.equal(result.dataSource, 'OpenStreetMap building footprints');
  assert.equal(result.routes[1].encodedPolyline, routes[1].encodedPolyline);
  assert.ok(result.routes[1].estimatedShadedMeters > 0);
});

test('one returned route stays one candidate and supplies no invented alternatives', async () => {
  const result = await calculateShadeRoute(request, {
    getWalkingRoutes: async () => ({routes: [returnedRoutes[0]]}),
    getTimeZone: async () => timeZone,
  }, manifest);
  assert.equal(result.routes.length, 1);
  assert.equal(result.choices.fastest, 'route-1');
  assert.equal(result.choices.balanced, 'route-1');
  assert.equal(result.choices.mostShade, 'route-1');
});

test('uncovered or mismatched route data is rejected before a shade claim', async () => {
  const mismatched = {...returnedRoutes[0],
    polyline: {encodedPolyline: '_p~iF~ps|U_ulLnnqC_mqNvxq`@'}};
  await assert.rejects(calculateShadeRoute(request, {
    getWalkingRoutes: async () => ({routes: [mismatched]}),
    getTimeZone: async () => timeZone,
  }, manifest), /does not match/);
  await assert.rejects(calculateShadeRoute(request, {
    getWalkingRoutes: async () => ({routes: returnedRoutes}),
    getTimeZone: async () => timeZone,
  }, path.resolve(__dirname, 'missing.json')));
});
