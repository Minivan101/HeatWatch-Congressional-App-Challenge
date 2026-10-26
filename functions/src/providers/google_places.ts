import {GeoPoint, validateGeoPoint} from "../shade/geometry";
import {NearbyIndoorPlace} from "../places/cool_spots";

export const NEARBY_FIELD_MASK =
  "places.id,places.displayName,places.location,places.formattedAddress";

export function buildNearbyIndoorRequest(
  center: GeoPoint, radiusMeters: number, apiKey: string,
) {
  validateGeoPoint(center);
  if (!Number.isFinite(radiusMeters) || radiusMeters <= 0 ||
    radiusMeters > 50000 || !apiKey.trim()) {
    throw new RangeError("Invalid nearby indoor search.");
  }
  return {
    url: "https://places.googleapis.com/v1/places:searchNearby",
    method: "POST" as const,
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": NEARBY_FIELD_MASK,
    },
    body: {
      includedTypes: ["restaurant", "cafe", "library"],
      maxResultCount: 20,
      rankPreference: "DISTANCE",
      locationRestriction: {circle: {center, radius: radiusMeters}},
    },
  };
}

export function parseNearbyIndoorResponse(
  payload: unknown, center: GeoPoint,
): NearbyIndoorPlace[] {
  validateGeoPoint(center);
  if (!payload || typeof payload !== "object") {
    throw new TypeError("Invalid Places response.");
  }
  const rawPlaces = (payload as {places?: unknown}).places;
  if (rawPlaces === undefined) return [];
  if (!Array.isArray(rawPlaces)) {
    throw new TypeError("Places response has an invalid places array.");
  }
  const seen = new Set<string>();
  return rawPlaces.map((raw) => {
    if (!raw || typeof raw !== "object") {
      throw new TypeError("Invalid place.");
    }
    const place = raw as Record<string, unknown>;
    const name = (place.displayName as {text?: unknown} | undefined)?.text;
    const location = place.location as GeoPoint;
    validateGeoPoint(location);
    if (typeof place.id !== "string" || !place.id.trim() ||
      typeof name !== "string" || !name.trim() ||
      typeof place.formattedAddress !== "string" ||
      !place.formattedAddress.trim() || seen.has(place.id)) {
      throw new TypeError("Place is missing required fields or is repeated.");
    }
    seen.add(place.id);
    const latMeters = (location.latitude - center.latitude) * 111320;
    const lonMeters = (location.longitude - center.longitude) *
      111320 * Math.cos(center.latitude * Math.PI / 180);
    return {
      placeId: place.id,
      name,
      location,
      address: place.formattedAddress,
      category: "INDOOR_PLACE" as const,
      openNow: null,
      distanceMeters: Math.hypot(latMeters, lonMeters),
      source: "GOOGLE_PLACES" as const,
    };
  });
}
