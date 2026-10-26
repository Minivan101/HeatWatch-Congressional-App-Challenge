const test = require('node:test');
const assert = require('node:assert/strict');
const {buildPublicAlertsUrl, parsePublicAlertsResponse} =
  require('../lib/providers/google_public_alerts.js');
const {createHeatGuardSnapshot} = require('../lib/weather/heat_guard.js');

const at = new Date('2026-06-21T16:00:00Z');
const current = {temperatureC: 32, feelsLikeC: 36,
  humidityPercent: 42, uvIndex: 8};
const heatAlert = (expiresAt = '2026-06-21T20:00:00Z') => ({
  alertId: 'fictional-1', eventType: 'HEAT',
  alertTitle: {text: 'Fictional heat advisory'},
  severity: 'SEVERE', expirationTime: expiresAt,
  dataSource: {name: 'Fictional Weather Authority',
    authorityUri: 'https://example.org/weather'},
});

test('public alert request is bounded and keeps its key server-side', () => {
  const url = new URL(buildPublicAlertsUrl(
    {latitude: 34, longitude: -118}, 'TEST_KEY'));
  assert.equal(url.pathname, '/v1/publicAlerts:lookup');
  assert.equal(url.searchParams.get('location.latitude'), '34');
  assert.equal(url.searchParams.get('pageSize'), '20');
  assert.equal(url.searchParams.get('key'), 'TEST_KEY');
});

test('active heat alert is normalized and precedes UV guidance', () => {
  const parsed = parsePublicAlertsResponse({weatherAlerts: [
    {eventType: 'WIND'}, heatAlert(),
  ]});
  assert.equal(parsed.alertsChecked, true);
  assert.equal(parsed.alerts.length, 1);
  assert.equal(parsed.alerts[0].severity, 'severe');
  const snapshot = createHeatGuardSnapshot(
    current, parsed.alerts, at, parsed.alertsChecked);
  assert.equal(snapshot.alerts[0].source, 'Fictional Weather Authority');
  assert.match(snapshot.guidance[0], /official alert/i);
});

test('expired heat alert is removed and checked-none differs from unchecked', () => {
  const expired = parsePublicAlertsResponse({weatherAlerts: [
    heatAlert('2026-06-21T15:00:00Z'),
  ]});
  const snapshot = createHeatGuardSnapshot(
    current, expired.alerts, at, expired.alertsChecked);
  assert.deepEqual(snapshot.alerts, []);
  assert.equal(snapshot.alertsChecked, true);
  assert.deepEqual(parsePublicAlertsResponse({weatherAlerts: []}),
    {alerts: [], alertsChecked: true});
  assert.throws(() => parsePublicAlertsResponse({}), /incomplete/);
  assert.throws(() => parsePublicAlertsResponse({weatherAlerts: [],
    nextPageToken: 'more'}), /incomplete/);
});

test('missing publisher and unsupported severity fail closed', () => {
  const missingSource = heatAlert();
  delete missingSource.dataSource;
  assert.throws(() => parsePublicAlertsResponse({
    weatherAlerts: [missingSource],
  }), /missing source/);
  assert.throws(() => parsePublicAlertsResponse({
    weatherAlerts: [{...heatAlert(), severity: 'SOMETHING_NEW'}],
  }), /Unknown/);
  assert.throws(() => parsePublicAlertsResponse({
    weatherAlerts: [heatAlert('2026-11-01T01:00:00')],
  }), /missing source or expiry/);
});
