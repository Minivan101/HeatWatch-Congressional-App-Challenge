const fs = require('node:fs');
const path = require('node:path');
const {createHeatGuardSnapshot} = require('../lib/weather/heat_guard.js');
const {parsePublicAlertsResponse} =
  require('../lib/providers/google_public_alerts.js');

function buildDemo() {
  return {
    ...createHeatGuardSnapshot({
      temperatureC: 32,
      feelsLikeC: 36,
      humidityPercent: 42,
      uvIndex: 8,
    }, [], new Date('2026-06-21T16:00:00Z'), false),
    sampleOnly: true,
    description: 'Invented example conditions. Not current weather.',
  };
}

module.exports = {buildDemo};

function buildScenarios() {
  const current = {temperatureC: 32, feelsLikeC: 36,
    humidityPercent: 42, uvIndex: 8};
  const at = new Date('2026-06-21T16:00:00Z');
  const recent = new Date('2026-06-21T15:50:00Z');
  const checked = parsePublicAlertsResponse({weatherAlerts: [{
    alertId: 'fictional-heat-example',
    eventType: 'HEAT',
    alertTitle: {text: 'Fictional heat advisory'},
    severity: 'SEVERE',
    expirationTime: '2026-06-21T19:00:00Z',
    dataSource: {name: 'Fictional Weather Authority',
      authorityUri: 'https://example.org/weather'},
  }]});
  return {
    sampleOnly: true,
    exampleAsOf: at.toISOString(),
    description: 'Fictional historical scenarios. Not current weather or '
      + 'an actual alert check.',
    scenarios: {
      active: createHeatGuardSnapshot(current, checked.alerts,
        recent, checked.alertsChecked),
      checkedNone: createHeatGuardSnapshot(current, [], recent, true),
      unchecked: createHeatGuardSnapshot(current, [], recent, false),
      stale: createHeatGuardSnapshot(current, [],
        new Date('2026-06-21T13:00:00Z'), true),
    },
  };
}

module.exports.buildScenarios = buildScenarios;

if (require.main === module) {
  const target = path.resolve(__dirname, '../../assets/heat_guard_demo.json');
  fs.writeFileSync(target, JSON.stringify(buildDemo(), null, 2) + '\n');
  const scenariosTarget = path.resolve(
    __dirname, '../../assets/heat_guard_scenarios.json');
  fs.writeFileSync(scenariosTarget,
    JSON.stringify(buildScenarios(), null, 2) + '\n');
  process.stdout.write(`Wrote ${target}\n`);
  process.stdout.write(`Wrote ${scenariosTarget}\n`);
}
