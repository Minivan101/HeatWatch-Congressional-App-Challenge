import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {parseShadeRouteCallableRequest} from "../shade/request";

export function loadShadeDemo(input: unknown): Record<string, unknown> {
  const trip = parseShadeRouteCallableRequest(input);
  const path = resolve(__dirname, "../../../assets/shade_demo.json");
  const data = JSON.parse(readFileSync(path, "utf8")) as
    Record<string, unknown>;
  if (data.sampleOnly !== true || !Array.isArray(data.routes)) {
    throw new TypeError("Shade demo must be labeled and contain routes.");
  }
  const origin = data.origin as {latitude: number; longitude: number};
  const destination = data.destination as
    {latitude: number; longitude: number};
  if (!origin || !destination ||
    trip.origin.latitude !== origin.latitude ||
    trip.origin.longitude !== origin.longitude ||
    trip.destination.latitude !== destination.latitude ||
    trip.destination.longitude !== destination.longitude ||
    trip.departureTime.toISOString() !== data.departureTime) {
    throw new RangeError("Only the saved demo trip is available locally.");
  }
  return data;
}
