const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {parseCuratedCenterDataset} =
  require('../lib/places/curated_centers.js');

const PROJECT_ID = 'heatwatch-nv';
const EMULATOR_HOST = '127.0.0.1:8080';

function assertLocalTarget(env) {
  if (env.FIRESTORE_EMULATOR_HOST !== EMULATOR_HOST ||
      env.GCLOUD_PROJECT !== PROJECT_ID) {
    throw new Error('Refusing to seed without the local Firestore emulator ' +
      `at ${EMULATOR_HOST} and project ${PROJECT_ID}.`);
  }
}

function loadSeedDataset() {
  const path = resolve(__dirname,
    '../../data/cooling_centers/clark_county_june_2026.json');
  return parseCuratedCenterDataset(JSON.parse(readFileSync(path, 'utf8')));
}

async function seed() {
  assertLocalTarget(process.env);
  const dataset = loadSeedDataset();
  initializeApp({projectId: PROJECT_ID});
  const db = getFirestore();
  const root = db.collection('coolingCenterDatasets').doc(dataset.datasetId);
  const batch = db.batch();
  const {centers, ...metadata} = dataset;
  batch.set(root, {...metadata, centerCount: centers.length});
  for (const center of centers) {
    batch.set(root.collection('centers').doc(center.id), center);
  }
  await batch.commit();
  const [savedRoot, savedCenters] = await Promise.all([
    root.get(), root.collection('centers').get(),
  ]);
  if (savedRoot.data()?.sourceUrl !== dataset.sourceUrl ||
      savedRoot.data()?.centerCount !== centers.length ||
      savedCenters.size !== centers.length ||
      !centers.every((center) => savedCenters.docs.some((saved) =>
        saved.id === center.id &&
        saved.data().validUntil === center.validUntil &&
        saved.data().sourceUrl === center.sourceUrl))) {
    throw new Error('Local Firestore readback did not match the county source.');
  }
  process.stdout.write(`Seeded ${centers.length} dated county records ` +
    `into the local Firestore emulator and verified readback: ` +
    `${dataset.datasetId}\n`);
}

module.exports = {assertLocalTarget, loadSeedDataset};

if (require.main === module) {
  seed().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
