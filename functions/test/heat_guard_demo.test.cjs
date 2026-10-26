const assert = require('node:assert/strict');
const test = require('node:test');
const {loadHeatGuardDemo} = require('../lib/demo/heat_guard_demo.js');

test('local Heat Guard callable payload stays historical and fictional', () => {
  const payload = loadHeatGuardDemo();
  assert.equal(payload.sampleOnly, true);
  assert.ok(Date.parse(payload.exampleAsOf) < Date.now());
  assert.equal(payload.scenario.alerts[0].title,
    'Fictional heat advisory');
  assert.equal(payload.scenario.current.temperatureC, 32);
});
