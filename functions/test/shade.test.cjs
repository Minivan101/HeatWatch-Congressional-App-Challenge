const test = require('node:test');
const assert = require('node:assert/strict');

const {solarPosition} = require('../lib/shade/solar.js');
const {shadowVector} = require('../lib/shade/shadows.js');
const {inferBuildingHeight} = require('../lib/shade/buildings.js');
const {
  shadeFractionFromSegments,
  balancedScore,
  rankRoutes,
} = require('../lib/shade/scoring.js');

test('solar position follows morning, midday, afternoon, and night', () => {
  const at = (date) => solarPosition(new Date(date), 34.0522, -118.2437, -7 * 3600);
  const morning = at('2026-06-21T16:00:00Z');
  const midday = at('2026-06-21T20:00:00Z');
  const afternoon = at('2026-06-22T00:00:00Z');
  const night = at('2026-06-21T07:00:00Z');

  assert.ok(midday.elevationDeg > morning.elevationDeg);
  assert.ok(midday.elevationDeg > afternoon.elevationDeg);
  assert.ok(morning.azimuthDeg < 180);
  assert.ok(afternoon.azimuthDeg > 180);
  assert.ok(night.elevationDeg < 0);
  assert.ok([morning, midday, afternoon, night].every((position) =>
    position.azimuthDeg >= 0 && position.azimuthDeg < 360));
});

test('solar calculation rejects invalid coordinates and timestamps', () => {
  assert.throws(() => solarPosition(new Date('bad'), 34, -118, -7 * 3600), RangeError);
  assert.throws(() => solarPosition(new Date(), 91, -118, -7 * 3600), RangeError);
});

test('shadow lengths and direction follow the geometric model', () => {
  const fortyFive = shadowVector(10, 45, 90);
  const thirty = shadowVector(10, 30, 90);
  assert.ok(Math.abs(fortyFive.lengthMeters - 10) < 0.01);
  assert.ok(Math.abs(thirty.lengthMeters - 17.3205) < 0.01);
  assert.ok(fortyFive.eastMeters < -9.99);
  assert.ok(Math.abs(fortyFive.northMeters) < 0.01);
  assert.equal(shadowVector(10, -2, 90), null);
  const lowSun = shadowVector(10, 0.1, 90);
  assert.equal(lowSun.lengthMeters, 250);
  assert.equal(lowSun.capped, true);
});

test('shade fraction weights distance rather than sample count', () => {
  assert.equal(shadeFractionFromSegments([{distanceMeters: 10, shaded: false}]), 0);
  assert.equal(shadeFractionFromSegments([{distanceMeters: 10, shaded: true}]), 1);
  assert.equal(shadeFractionFromSegments([
    {distanceMeters: 5, shaded: true},
    {distanceMeters: 15, shaded: false},
  ]), 0.25);
  assert.throws(() => shadeFractionFromSegments([]), RangeError);
});

test('route ranking respects time, shade, and detour limit', () => {
  const routes = [
    {id: 'fast', durationSeconds: 600, shadeFraction: 0.1},
    {id: 'balanced', durationSeconds: 660, shadeFraction: 0.7},
    {id: 'shady', durationSeconds: 840, shadeFraction: 0.8},
    {id: 'too-long', durationSeconds: 1200, shadeFraction: 1},
  ];
  const ranked = rankRoutes(routes);
  assert.equal(ranked.fastest.id, 'fast');
  assert.equal(ranked.balanced.id, 'balanced');
  assert.equal(ranked.mostShade.id, 'shady');
  assert.ok(balancedScore(0.7, 660, 600) > balancedScore(0.1, 600, 600));
});

test('night mode and one-route cases never fabricate alternatives', () => {
  const only = {id: 'only', durationSeconds: 600, shadeFraction: 0.4};
  const day = rankRoutes([only]);
  assert.equal(day.fastest.id, 'only');
  assert.equal(day.balanced.id, 'only');
  assert.equal(day.mostShade.id, 'only');

  const night = rankRoutes([only], {nightMode: true});
  assert.equal(night.fastest.id, 'only');
  assert.equal(night.balanced, null);
  assert.equal(night.mostShade, null);
});

test('building height uses OSM height, levels, then documented assumption', () => {
  assert.deepEqual(inferBuildingHeight({height: '12.5 m', 'building:levels': '8'}), {
    heightMeters: 12.5, confidence: 'high', source: 'height',
  });
  assert.deepEqual(inferBuildingHeight({'building:levels': '3'}), {
    heightMeters: 9, confidence: 'medium', source: 'building:levels',
  });
  assert.deepEqual(inferBuildingHeight({height: 'invalid'}), {
    heightMeters: 9, confidence: 'low', source: 'assumed',
  });
});

test('UV guidance follows low, moderate-to-high, and very-high categories', () => {
  const {uvGuidance} = require('../lib/weather/guidance.js');
  assert.equal(uvGuidance(2).category, 'low');
  assert.equal(uvGuidance(3).category, 'moderate-to-high');
  assert.equal(uvGuidance(7).category, 'moderate-to-high');
  assert.equal(uvGuidance(8).category, 'very-high-to-extreme');
  assert.throws(() => uvGuidance(-1), RangeError);
});

test('NOAA date checkpoints include January 1 and leap day; UTC instant ignores display zone', () => {
  const cases = [
    ['2026-01-01T20:00:00Z', 30.654282756277865, 184.2277938569751],
    ['2024-02-29T20:00:00Z', 45.96812064310438, 182.13371643682592],
  ];
  for (const [iso, elevation, azimuth] of cases) {
    const position = solarPosition(new Date(iso), 36.195, -115.285, 0);
    assert.ok(Math.abs(position.elevationDeg - elevation) < 1e-8);
    assert.ok(Math.abs(position.azimuthDeg - azimuth) < 1e-8);
    assert.deepEqual(position, solarPosition(new Date(iso), 36.195, -115.285, -8 * 3600));
  }
});
