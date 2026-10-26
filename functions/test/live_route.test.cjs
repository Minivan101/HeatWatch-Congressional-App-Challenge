const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const {routes} = require('../scripts/build_shade_demo.cjs');
const {calculateLiveShadeRoute} = require('../lib/shade/live_route.js');

const manifest = path.resolve(__dirname, '../../data/buildings/demo_las_vegas/manifest.json');
const request = {
  origin: {latitude: 36.18998, longitude: -115.28460},
  destination: {latitude: 36.18998, longitude: -115.28380},
  departureTime: new Date('2026-06-21T16:00:00Z'),
};

test('live transport joins returned routes, route-local zone and OSM coverage', async () => {
  const calls = [];
  const fakeFetch = async (url, options) => {
    calls.push({url, options});
    if (url.includes('computeRoutes')) {
      return {ok: true, json: async () => ({routes: routes.map((route) => ({
        duration: `${route.durationSeconds}s`,
        distanceMeters: 140,
        polyline: {encodedPolyline: route.encodedPolyline},
      }))})};
    }
    return {ok: true, json: async () => ({
      status: 'OK', rawOffset: -28800, dstOffset: 3600,
      timeZoneId: 'America/Los_Angeles',
    })};
  };
  const result = await calculateLiveShadeRoute(
    request, manifest, 'TEST_KEY', fakeFetch);
  assert.equal(result.sampleOnly, false);
  assert.equal(result.routeSource, 'Google Routes API walking candidates');
  assert.equal(result.timeZoneId, 'America/Los_Angeles');
  assert.equal(result.routes.length, 3);
  assert.ok(result.buildingCount > 0);
  assert.equal(calls.length, 2);
  assert.equal(calls[0].options.headers['X-Goog-Api-Key'], 'TEST_KEY');
  assert.equal(new URL(calls[1].url).searchParams.get('key'), 'TEST_KEY');
  assert.notEqual(new URL(calls[1].url).searchParams.get('location'),
    `${request.origin.latitude},${request.origin.longitude}`);
});

test('provider failure cannot expose the secret through its own error', async () => {
  await assert.rejects(calculateLiveShadeRoute(request, manifest,
    'TEST_KEY', async () => ({ok: false, status: 403})),
  (error) => error.message === 'Routes provider failed (403).' &&
    !error.message.includes('TEST_KEY'));
});
