const fs = require('node:fs');
const path = require('node:path');
const {createCoolSpotsSnapshot} = require('../lib/places/cool_spots.js');

function buildDemo() {
  const location = {latitude: 36.118134, longitude: -115.143604};
  const snapshot = createCoolSpotsSnapshot([{
    id: 'fictional-center',
    name: 'Fictional Community Center',
    location,
    address: 'Invented address for interface testing',
    category: 'OFFICIAL_COOLING_CENTER',
    sourceAgency: 'Fictional Example Agency',
    sourceUrl: 'https://example.com/',
    validFrom: '2026-06-01',
    validUntil: '2026-09-30',
    lastVerifiedAt: '2026-06-20T12:00:00Z',
    hours: 'Example hours only',
  }], [{
    placeId: 'fictional-cafe',
    name: 'Fictional Cafe',
    location: {latitude: 36.1186, longitude: -115.1443},
    address: 'Invented address for interface testing',
    category: 'INDOOR_PLACE',
    openNow: null,
    distanceMeters: 82,
    source: 'FICTIONAL_FIXTURE',
  }], new Date('2026-06-21T16:00:00Z'));
  return {
    ...snapshot,
    sampleOnly: true,
    description: 'Fictional interface examples. Not real or verified places.',
  };
}

module.exports = {buildDemo};

if (require.main === module) {
  const target = path.resolve(__dirname, '../../assets/cool_spots_demo.json');
  fs.writeFileSync(target, JSON.stringify(buildDemo(), null, 2) + '\n');
  process.stdout.write(`Wrote ${target}\n`);
}
