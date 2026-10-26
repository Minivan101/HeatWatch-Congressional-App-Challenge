const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {parseCuratedCenterDataset} =
  require('../lib/places/curated_centers.js');
const {createCoolSpotsSnapshot} =
  require('../lib/places/cool_spots.js');

const file = path.resolve(__dirname,
  '../../data/cooling_centers/clark_county_june_2026.json');

test('county PDF records have source, hours and past activation dates', () => {
  const data = parseCuratedCenterDataset(JSON.parse(
    fs.readFileSync(file, 'utf8')));
  assert.equal(data.centers.length, 2);
  assert.equal(data.sourceAgency, 'Clark County, Nevada');
  assert.ok(data.sourceUrl.endsWith('.pdf'));
  assert.ok(data.centers.every((center) =>
    center.validFrom === '2026-06-04' &&
    center.validUntil === '2026-06-05' &&
    center.locationSourceUrl.startsWith('https://') &&
    center.hours.length > 0));
  const now = createCoolSpotsSnapshot(data.centers, [],
    new Date('2026-09-27T20:00:00Z'));
  assert.deepEqual(now.officialCenters, []);
  const duringEvent = createCoolSpotsSnapshot(data.centers, [],
    new Date('2026-06-04T20:00:00Z'));
  assert.equal(duringEvent.officialCenters.length, 2);
});

test('source mismatch or invalid dates cannot enter curated dataset', () => {
  const data = JSON.parse(fs.readFileSync(file, 'utf8'));
  assert.throws(() => parseCuratedCenterDataset({...data,
    centers: [{...data.centers[0], validUntil: '2026-05-01'}]}));
  assert.throws(() => parseCuratedCenterDataset({...data,
    centers: [{...data.centers[0], sourceUrl: 'https://example.com'}]}));
});
