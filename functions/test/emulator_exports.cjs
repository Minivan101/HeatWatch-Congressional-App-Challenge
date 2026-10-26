const test = require("node:test");
const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const path = require("node:path");

test("diagnostic Admin writes and sample callables are exported only locally", () => {
  for (const local of [false, true]) {
    const env = {...process.env};
    delete env.FUNCTIONS_EMULATOR;
    if (local) env.FUNCTIONS_EMULATOR = "true";
    const result = spawnSync(process.execPath, ["-e",
      "process.stdout.write(JSON.stringify(Object.keys(require('./lib/index.js')).sort()))"],
      {cwd: path.resolve(__dirname, ".."), env, encoding: "utf8"});
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), local ?
      ["getCoolSpotsDemo", "getHeatGuardDemo", "getLocalCoolingCenters", "getShadeRouteDemo", "healthCheck"] : []);
  }
});
