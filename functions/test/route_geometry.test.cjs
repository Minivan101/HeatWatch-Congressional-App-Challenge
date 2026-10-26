const test = require('node:test');
const assert = require('node:assert/strict');

const {decodePolyline, projectLocal} = require('../lib/shade/geometry.js');
const {sampleRoute} = require('../lib/shade/route_sampling.js');
const {pointInSweptShadow} = require('../lib/shade/shadow_geometry.js');
const {shadowVector} = require('../lib/shade/shadows.js');

test('Google encoded polyline decodes known coordinates', () => {
  assert.deepEqual(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@'), [
    {latitude: 38.5, longitude: -120.2},
    {latitude: 40.7, longitude: -120.95},
    {latitude: 43.252, longitude: -126.453},
  ]);
  assert.throws(() => decodePolyline('_p~iF~ps|U_'), RangeError);
});

test('local projection and route samples use meters and distance weights', () => {
  const origin = {latitude: 34, longitude: -118};
  const point = {latitude: 34, longitude: -117.9997};
  const east = projectLocal(point, origin).eastMeters;
  assert.ok(east > 27 && east < 28);

  const route = sampleRoute([origin, point], 10);
  assert.equal(route.samples.length, 3);
  assert.ok(Math.abs(route.totalDistanceMeters - east) < 0.001);
  assert.ok(route.samples.every((sample) =>
    sample.representedDistanceMeters <= 10));
  assert.ok(Math.abs(route.samples.reduce((sum, sample) =>
    sum + sample.representedDistanceMeters, 0) - east) < 0.001);
  assert.ok(route.samples[0].cumulativeDistanceMeters <
    route.samples[1].cumulativeDistanceMeters);
  assert.throws(() => sampleRoute([origin, origin]), RangeError);
});

test('building shadow covers points west of an east-lit building', () => {
  const building = [
    {eastMeters: 0, northMeters: 0},
    {eastMeters: 10, northMeters: 0},
    {eastMeters: 10, northMeters: 10},
    {eastMeters: 0, northMeters: 10},
  ];
  const shadow = shadowVector(10, 45, 90);
  assert.equal(pointInSweptShadow(
    {eastMeters: -5, northMeters: 5}, building, shadow), true);
  assert.equal(pointInSweptShadow(
    {eastMeters: 15, northMeters: 5}, building, shadow), false);
  assert.equal(pointInSweptShadow(
    {eastMeters: -5, northMeters: 12}, building, shadow), false);
  assert.equal(pointInSweptShadow(
    {eastMeters: -10, northMeters: 5}, building, shadow), true);
});
