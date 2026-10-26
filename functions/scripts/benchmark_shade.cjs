const {performance} = require('node:perf_hooks');
const path = require('node:path');
const {estimateShadeRoutes} = require('../lib/shade/estimate.js');
const {expandedRouteBounds, loadPreparedBuildings} =
  require('../lib/shade/prepared_buildings.js');
const {routes} = require('./build_shade_demo.cjs');

const departure = new Date('2026-06-21T16:00:00Z');

function medianMilliseconds(buildings, useIndex) {
  for (let n = 0; n < 10; n++) {
    estimateShadeRoutes(routes, buildings, departure, -7 * 3600, useIndex);
  }
  const timings = [];
  for (let n = 0; n < 30; n++) {
    const start = performance.now();
    estimateShadeRoutes(routes, buildings, departure, -7 * 3600, useIndex);
    timings.push(performance.now() - start);
  }
  timings.sort((a, b) => a - b);
  return timings[15].toFixed(3);
}

async function main() {
  const manifest = path.resolve(__dirname,
    '../../data/buildings/demo_las_vegas/manifest.json');
  const source = await loadPreparedBuildings(manifest,
    expandedRouteBounds(routes));
  const dense = Array.from({length: 300}, (_, index) => {
    const building = source[index % source.length];
    const offset = Math.floor(index / source.length) * 0.005;
    return {
      tags: building.tags,
      footprint: building.footprint.map((point) => ({
        latitude: point.latitude + offset,
        longitude: point.longitude + offset,
      })),
    };
  });
  for (const [label, buildings] of [
    ['saved example', source], ['synthetic scaling case', dense],
  ]) {
    const indexed = medianMilliseconds(buildings, true);
    const brute = medianMilliseconds(buildings, false);
    process.stdout.write(`${label}: ${buildings.length} buildings, ` +
      `indexed ${indexed} ms, brute ${brute} ms (median of 30)\n`);
  }
}

main().catch((error) => {
  process.stderr.write(`${error}\n`);
  process.exitCode = 1;
});
