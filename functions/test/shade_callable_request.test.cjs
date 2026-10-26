const test = require('node:test');
const assert = require('node:assert/strict');
const {parseShadeRouteCallableRequest} =
  require('../lib/shade/request.js');
const {loadShadeDemo} = require('../lib/demo/shade_demo.js');

const trip = {
  origin: {lat: 36.18998, lng: -115.28460},
  destination: {lat: 36.18998, lng: -115.28380},
  departureTime: '2026-06-21T16:00:00.000Z',
};

test('callable trip is validated and converted to engine coordinates', () => {
  const parsed = parseShadeRouteCallableRequest(trip);
  assert.deepEqual(parsed.origin,
    {latitude: 36.18998, longitude: -115.28460});
  assert.equal(parsed.departureTime.toISOString(), trip.departureTime);
  assert.throws(() => parseShadeRouteCallableRequest(
    {...trip, origin: {lat: 100, lng: 0}}));
  assert.throws(() => parseShadeRouteCallableRequest(
    {...trip, destination: trip.origin}));
  assert.throws(() => parseShadeRouteCallableRequest(
    {...trip, departureTime: '2026-06-21T16:00:00'}));
});

test('demo callable accepts only its saved trip', () => {
  const result = loadShadeDemo(trip);
  assert.equal(result.sampleOnly, true);
  assert.equal(result.routes.length, 3);
  assert.throws(() => loadShadeDemo({
    ...trip, origin: {lat: 36.1699, lng: -115.1398},
  }), /saved demo trip/);
  assert.throws(() => loadShadeDemo({
    ...trip, departureTime: '2026-06-21T17:00:00.000Z',
  }), /saved demo trip/);
});
