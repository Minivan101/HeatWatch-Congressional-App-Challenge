import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {parseCuratedCenterDataset} from "../places/curated_centers";
import {parseNearbyIndoorResponse} from "../providers/google_places";
import {validateGeoPoint} from "../shade/geometry";

export function loadCoolSpotsDemo(input: unknown): Record<string, unknown> {
  const path = resolve(__dirname,
    "../../../data/cooling_centers/clark_county_june_2026.json");
  const dataset = parseCuratedCenterDataset(JSON.parse(
    readFileSync(path, "utf8")) as unknown);
  const reference = dataset.sampleReference.location;
  if (!input || typeof input !== "object") {
    throw new RangeError("Only the saved local search is available.");
  }
  const request = input as Record<string, unknown>;
  const location = request.location as typeof reference;
  try {
    validateGeoPoint(location);
  } catch {
    throw new RangeError("Only the saved local search is available.");
  }
  if (location.latitude !== reference.latitude ||
    location.longitude !== reference.longitude ||
    request.radiusMeters !== 1500) {
    throw new RangeError("Only the saved local search is available.");
  }
  const fixture = {places: [{
    id: "fictional-cafe",
    displayName: {text: "Fictional Cafe"},
    location: {latitude: 36.1186, longitude: -115.1443},
    formattedAddress: "Invented address for interface testing",
  }]};
  const indoorPlaces = parseNearbyIndoorResponse(fixture, reference)
    .map((place) => ({...place, source: "FICTIONAL_FIXTURE" as const}));
  return {
    sampleOnly: true,
    checkedAt: "2026-06-21T16:00:00.000Z",
    referenceLocation: reference,
    indoorPlaces,
    description: "Fictional historical Places-shaped response. " +
      "No live business search was made.",
  };
}
