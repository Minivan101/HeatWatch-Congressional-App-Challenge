const fs = require('node:fs');
const path = require('node:path');

const {calculateShadeRoute} = require('../lib/shade/calculate_route.js');

const point = (latitude, longitude) => ({latitude, longitude});
const encode = (points) => {
  let previousLatitude = 0;
  let previousLongitude = 0;
  let result = '';
  for (const coordinate of points) {
    const latitude = Math.round(coordinate.latitude * 1e5);
    const longitude = Math.round(coordinate.longitude * 1e5);
    for (const delta of [
      latitude - previousLatitude,
      longitude - previousLongitude,
    ]) {
      let value = delta < 0 ? ~(delta << 1) : delta << 1;
      while (value >= 0x20) {
        result += String.fromCharCode((0x20 | (value & 0x1f)) + 63);
        value >>= 5;
      }
      result += String.fromCharCode(value + 63);
    }
    previousLatitude = latitude;
    previousLongitude = longitude;
  }
  return result;
};

const routes = [
  {
    id: 'direct',
    durationSeconds: 75,
    encodedPolyline: encode([
      point(36.18998, -115.28460), point(36.18998, -115.28380),
    ]),
  },
  {
    id: 'north',
    durationSeconds: 100,
    encodedPolyline: encode([
      point(36.18998, -115.28460), point(36.19010, -115.28460),
      point(36.19010, -115.28380), point(36.18998, -115.28380),
    ]),
  },
  {
    id: 'south',
    durationSeconds: 115,
    encodedPolyline: encode([
      point(36.18998, -115.28460), point(36.18980, -115.28460),
      point(36.18980, -115.28380), point(36.18998, -115.28380),
    ]),
  },
];

const manifestPath = path.resolve(
  __dirname, '../../data/buildings/demo_las_vegas/manifest.json');
const departureTime = new Date('2026-06-21T16:00:00Z');
const utcOffsetSeconds = -7 * 3600;

async function buildEstimate() {
  const estimate = await calculateShadeRoute({
    origin: point(36.18998, -115.28460),
    destination: point(36.18998, -115.28380),
    departureTime,
  }, {
    getWalkingRoutes: async () => ({
      routes: routes.map((route, index) => ({
        duration: `${route.durationSeconds}s`,
        distanceMeters: 72 + index * 20,
        polyline: {encodedPolyline: route.encodedPolyline},
      })),
    }),
    getTimeZone: async () => ({
      status: 'OK',
      rawOffset: utcOffsetSeconds - 3600,
      dstOffset: 3600,
      timeZoneId: 'America/Los_Angeles',
    }),
  }, manifestPath);
  return {
    ...estimate,
    sampleOnly: true,
    origin: point(36.18998, -115.28460),
    departureTime: departureTime.toISOString(),
    destination: {
      id: 'demo-east-end',
      label: 'Demo destination',
      latitude: 36.18998,
      longitude: -115.28380,
    },
    source: 'OpenStreetMap building footprints',
    description: 'Invented route lines in Las Vegas at 9 AM on June 21; '
      + 'saved Las Vegas OpenStreetMap footprints; missing heights use the demo-only 9 m assumption. Not walking directions.',
  };
}

module.exports = {routes, buildEstimate};

if (require.main === module) {
  buildEstimate().then((output) => {
    const target = path.resolve(__dirname, '../../assets/shade_demo.json');
    fs.mkdirSync(path.dirname(target), {recursive: true});
    fs.writeFileSync(target, JSON.stringify(output, null, 2) + '\n');
    process.stdout.write(`Wrote ${target}\n`);
  }).catch((error) => {
    process.stderr.write(`${error}\n`);
    process.exitCode = 1;
  });
}
