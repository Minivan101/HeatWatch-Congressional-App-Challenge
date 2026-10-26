const test = require('node:test');
const assert = require('node:assert/strict');
const routesFixture = require('./fixtures/routes_response.json');
const timezoneFixture = require('./fixtures/timezone_response.json');
const {buildWalkingRoutesRequest, parseWalkingRoutesResponse,
  WALKING_ROUTE_FIELD_MASK} = require('../lib/providers/google_routes.js');
const {buildTimeZoneUrl, parseTimeZoneResponse} =
  require('../lib/providers/google_timezone.js');

const origin = {latitude: 34, longitude: -118};
const destination = {latitude: 34.001, longitude: -118.001};

test('walking route request asks for alternatives and only needed fields', () => {
  const request = buildWalkingRoutesRequest(origin, destination, 'TEST_KEY');
  assert.equal(request.method, 'POST');
  assert.equal(request.body.travelMode, 'WALK');
  assert.equal(request.body.computeAlternativeRoutes, true);
  assert.equal(request.headers['X-Goog-FieldMask'], WALKING_ROUTE_FIELD_MASK);
  assert.ok(!request.headers['X-Goog-FieldMask'].includes('*'));
  assert.equal(request.body.origin.location.latLng.latitude, 34);
  assert.throws(() => buildWalkingRoutesRequest(origin, origin, 'TEST_KEY'));
});

test('local Routes fixture provides unique model inputs without invented alternatives', () => {
  const parsed = parseWalkingRoutesResponse(routesFixture);
  assert.deepEqual(parsed.map((route) => route.id), ['route-1', 'route-2']);
  assert.equal(parsed[0].durationSeconds, 600);
  assert.equal(parseWalkingRoutesResponse({routes: [
    routesFixture.routes[0], routesFixture.routes[0],
  ]}).length, 1);
  assert.throws(() => parseWalkingRoutesResponse({routes: []}));
  assert.throws(() => parseWalkingRoutesResponse({routes: [{duration: '2s'}]}));
});

test('Time Zone fixture supplies UTC plus DST offset', () => {
  const date = new Date('2026-06-21T16:00:00Z');
  const url = new URL(buildTimeZoneUrl(origin, date, 'TEST_KEY'));
  assert.equal(url.searchParams.get('location'), '34,-118');
  assert.equal(url.searchParams.get('timestamp'), String(date.getTime() / 1000));
  assert.deepEqual(parseTimeZoneResponse(timezoneFixture), {
    timeZoneId: 'America/Los_Angeles', utcOffsetSeconds: -25200,
  });
  assert.throws(() => parseTimeZoneResponse({status: 'REQUEST_DENIED'}));
  assert.throws(() => buildTimeZoneUrl(origin, new Date(NaN), 'TEST_KEY'));
});
