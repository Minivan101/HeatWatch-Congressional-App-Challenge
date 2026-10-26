const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHeatGuardSnapshot} = require('../lib/weather/heat_guard.js');
const {buildDemo} = require('../scripts/build_heat_guard_demo.cjs');

const at = new Date('2026-06-21T16:00:00Z');
const weather = {
  temperatureC: 32, feelsLikeC: 36, humidityPercent: 42, uvIndex: 8,
};

test('official active alert is first and expired alerts are removed', () => {
  const alerts = [
    {title: 'Expired', severity: 'moderate', source: 'Agency',
      sourceUrl: 'https://example.gov/expired',
      expiresAt: '2026-06-21T15:00:00Z'},
    {title: 'Active', severity: 'severe', source: 'Agency',
      sourceUrl: 'https://example.gov/active',
      expiresAt: '2026-06-21T20:00:00Z'},
  ];
  const result = createHeatGuardSnapshot(weather, alerts, at, true);
  assert.deepEqual(result.alerts.map((alert) => alert.title), ['Active']);
  assert.match(result.guidance[0], /official alert/);
  assert.match(result.guidance[1], /extra sun protection/i);
});

test('unchecked alerts are not presented as an empty live alert search', () => {
  const result = createHeatGuardSnapshot(weather, [], at, false);
  assert.equal(result.alertsChecked, false);
  assert.equal(result.alerts.length, 0);
  assert.throws(() => createHeatGuardSnapshot(weather, [{title: 'A'}], at, false));
});

test('alert expiry uses absolute instants across Pacific DST changes', () => {
  const alert = (expiresAt) => ({title: 'Example', severity: 'severe',
    source: 'Agency', sourceUrl: 'https://example.gov/alert', expiresAt});
  const spring = new Date('2026-03-08T10:00:00Z');
  assert.equal(createHeatGuardSnapshot(weather,
    [alert('2026-03-08T01:59:59-08:00')], spring, true).alerts.length, 0);
  assert.equal(createHeatGuardSnapshot(weather,
    [alert('2026-03-08T03:00:01-07:00')], spring, true).alerts.length, 1);
  const fall = new Date('2026-11-01T09:00:00Z');
  assert.equal(createHeatGuardSnapshot(weather,
    [alert('2026-11-01T01:59:59-07:00')], fall, true).alerts.length, 0);
  assert.equal(createHeatGuardSnapshot(weather,
    [alert('2026-11-01T01:00:01-08:00')], fall, true).alerts.length, 1);
  assert.throws(() => createHeatGuardSnapshot(weather,
    [alert('2026-11-01T01:00:00')], fall, true), /Invalid official alert/);
});

test('generated Heat Guard demo stays explicitly invented', () => {
  const asset = JSON.parse(fs.readFileSync(path.resolve(
    __dirname, '../../assets/heat_guard_demo.json'), 'utf8'));
  assert.deepEqual(asset, buildDemo());
  assert.equal(asset.sampleOnly, true);
});
