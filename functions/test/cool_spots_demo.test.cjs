const assert = require('node:assert/strict');
const test = require('node:test');
const {loadCoolSpotsDemo} = require('../lib/demo/cool_spots_demo.js');

const location = {latitude: 36.1179, longitude: -115.1428};

test('local Places-shaped response stays fictional and separate', () => {
  const result = loadCoolSpotsDemo({location, radiusMeters: 1500});
  assert.equal(result.sampleOnly, true);
  assert.ok(Date.parse(result.checkedAt) < Date.now());
  assert.deepEqual(result.referenceLocation, location);
  assert.equal(result.indoorPlaces.length, 1);
  assert.equal(result.indoorPlaces[0].source, 'FICTIONAL_FIXTURE');
  assert.equal(result.indoorPlaces[0].name, 'Fictional Cafe');
  assert.equal(result.indoorPlaces[0].openNow, null);
  assert.equal(result.officialCenters, undefined);
});

test('local response refuses arbitrary location and radius', () => {
  assert.throws(() => loadCoolSpotsDemo({
    location: {latitude: 36.12, longitude: -115.1428}, radiusMeters: 1500,
  }), RangeError);
  assert.throws(() => loadCoolSpotsDemo({location, radiusMeters: 3000}),
    RangeError);
});
