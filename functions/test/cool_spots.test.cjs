const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createCoolSpotsSnapshot} = require('../lib/places/cool_spots.js');
const {buildDemo} = require('../scripts/build_cool_spots_demo.cjs');

test('official centers and businesses stay separate; expired centers vanish', () => {
  const demo = buildDemo();
  const expired = {...demo.officialCenters[0], id: 'old',
    validUntil: '2026-06-20'};
  const result = createCoolSpotsSnapshot(
    [demo.officialCenters[0], expired], demo.indoorPlaces,
    new Date('2026-06-21T16:00:00Z'));
  assert.deepEqual(result.officialCenters.map((center) => center.id),
    ['fictional-center']);
  assert.equal(result.indoorPlaces.length, 1);
  assert.equal(result.indoorPlaces[0].category, 'INDOOR_PLACE');
});

test('an indoor business cannot be misclassified as an official center', () => {
  const demo = buildDemo();
  assert.throws(() => createCoolSpotsSnapshot(
    [{...demo.indoorPlaces[0], category: 'OFFICIAL_COOLING_CENTER'}],
    [], new Date('2026-06-21T16:00:00Z')));
});

test('Cool Spots asset remains fictional and reproducible', () => {
  const asset = JSON.parse(fs.readFileSync(path.resolve(
    __dirname, '../../assets/cool_spots_demo.json'), 'utf8'));
  assert.deepEqual(asset, buildDemo());
  assert.equal(asset.sampleOnly, true);
});
