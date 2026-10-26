const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {solarPosition} = require('../lib/shade/solar.js');

test('legacy solar helper stays within independent Las Vegas SPA envelope', () => {
  const reference = JSON.parse(fs.readFileSync(
    path.resolve(__dirname, '../../test/fixtures/solar_reference.json'), 'utf8'));
  assert.equal(reference.cases.length, 3170);
  const rad = Math.PI / 180;
  for (const [at, lat, lon, elevation, azimuth] of reference.cases) {
    const actual = solarPosition(new Date(at), lat, lon, 0);
    const azimuthError = Math.abs(
      ((actual.azimuthDeg - azimuth + 540) % 360) - 180);
    const cosine = Math.sin(actual.elevationDeg * rad) * Math.sin(elevation * rad) +
      Math.cos(actual.elevationDeg * rad) * Math.cos(elevation * rad) *
      Math.cos((actual.azimuthDeg - azimuth) * rad);
    const directionError = Math.acos(Math.max(-1, Math.min(1, cosine))) / rad;
    assert.ok(Math.abs(actual.elevationDeg - elevation) < 1, at);
    assert.ok(azimuthError < 1, at);
    assert.ok(directionError < 1, at);
    if (Math.abs(elevation) >= 1) {
      assert.equal(actual.elevationDeg > 0, elevation > 0, at);
    }
  }
});
