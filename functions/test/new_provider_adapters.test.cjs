const test = require('node:test');
const assert = require('node:assert/strict');
const placesFixture = require('./fixtures/places_nearby_response.json');
const weatherFixture = require('./fixtures/weather_current_response.json');
const {buildNearbyIndoorRequest, parseNearbyIndoorResponse,
  NEARBY_FIELD_MASK} = require('../lib/providers/google_places.js');
const {buildCurrentConditionsUrl, parseCurrentConditionsResponse} =
  require('../lib/providers/google_weather.js');
const {createCoolSpotsSnapshot} = require('../lib/places/cool_spots.js');
const {createHeatGuardSnapshot} = require('../lib/weather/heat_guard.js');

const center = {latitude: 34, longitude: -118};

test('Places request is bounded and maps to indoor category only', () => {
  const request = buildNearbyIndoorRequest(center, 2000, 'TEST_KEY');
  assert.equal(request.method, 'POST');
  assert.equal(request.headers['X-Goog-FieldMask'], NEARBY_FIELD_MASK);
  assert.ok(!NEARBY_FIELD_MASK.includes('currentOpeningHours'));
  assert.throws(() => buildNearbyIndoorRequest(center, 50001, 'TEST_KEY'));
  const places = parseNearbyIndoorResponse(placesFixture, center);
  assert.equal(places[0].category, 'INDOOR_PLACE');
  assert.equal(places[0].openNow, null);
  assert.ok(places[0].distanceMeters > 0);
  assert.deepEqual(parseNearbyIndoorResponse({}, center), []);
  assert.equal(createCoolSpotsSnapshot([], places,
    new Date('2026-06-21T16:00:00Z')).officialCenters.length, 0);
  assert.throws(() => parseNearbyIndoorResponse({places: [{}]}, center));
});

test('Weather response feeds Heat Guard without claiming alert checks', () => {
  const url = new URL(buildCurrentConditionsUrl(center, 'TEST_KEY'));
  assert.equal(url.searchParams.get('unitsSystem'), 'METRIC');
  assert.equal(url.searchParams.get('location.latitude'), '34');
  const parsed = parseCurrentConditionsResponse(weatherFixture);
  assert.equal(parsed.observation.feelsLikeC, 36);
  const snapshot = createHeatGuardSnapshot(parsed.observation,
    [], parsed.observedAt, false);
  assert.equal(snapshot.alertsChecked, false);
  assert.throws(() => parseCurrentConditionsResponse(
    {...weatherFixture, temperature: {degrees: 90, unit: 'FAHRENHEIT'}}));
  assert.throws(() => parseCurrentConditionsResponse(
    {...weatherFixture, currentTime: 'invalid'}));
});
