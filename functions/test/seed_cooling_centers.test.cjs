const assert = require('node:assert/strict');
const test = require('node:test');
const {assertLocalTarget, loadSeedDataset} =
  require('../scripts/seed_cooling_centers.cjs');

test('cooling-center seed accepts only the local emulator target', () => {
  assert.doesNotThrow(() => assertLocalTarget({
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
    GCLOUD_PROJECT: 'heatwatch-nv',
  }));
  assert.throws(() => assertLocalTarget({
    GCLOUD_PROJECT: 'heatwatch-nv',
  }), /Refusing to seed/);
  assert.throws(() => assertLocalTarget({
    FIRESTORE_EMULATOR_HOST: 'firestore.googleapis.com',
    GCLOUD_PROJECT: 'heatwatch-nv',
  }), /Refusing to seed/);
  assert.throws(() => assertLocalTarget({
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
    GCLOUD_PROJECT: 'some-other-project',
  }), /Refusing to seed/);
});

test('cooling-center seed carries county source and expired dates', () => {
  const dataset = loadSeedDataset();
  assert.equal(dataset.centers.length, 2);
  assert.ok(dataset.centers.every((center) =>
    center.sourceUrl === dataset.sourceUrl &&
    center.validUntil < '2026-09-28'));
});
