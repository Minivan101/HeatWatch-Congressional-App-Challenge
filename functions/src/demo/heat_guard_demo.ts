import {readFileSync} from "node:fs";
import {resolve} from "node:path";

export function loadHeatGuardDemo(): Record<string, unknown> {
  const path = resolve(__dirname, "../../../assets/heat_guard_scenarios.json");
  const saved = JSON.parse(readFileSync(path, "utf8")) as
    Record<string, unknown>;
  const scenarios = saved.scenarios as Record<string, unknown> | undefined;
  const scenario = scenarios?.active as Record<string, unknown> | undefined;
  if (saved.sampleOnly !== true ||
    typeof saved.exampleAsOf !== "string" ||
    !Number.isFinite(Date.parse(saved.exampleAsOf)) ||
    !scenario || !Array.isArray(scenario.alerts) ||
    scenario.current === undefined ||
    typeof scenario.fetchedAt !== "string") {
    throw new TypeError("Heat Guard demo is incomplete or not labeled.");
  }
  return {
    sampleOnly: true,
    exampleAsOf: saved.exampleAsOf,
    description: saved.description,
    scenario,
  };
}
