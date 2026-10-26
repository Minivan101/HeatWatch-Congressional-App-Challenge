import {GeoPoint, validateGeoPoint} from "./geometry";
import {ShadeRouteRequest} from "./calculate_route";

export function parseShadeRouteCallableRequest(
  input: unknown,
): ShadeRouteRequest {
  if (!input || typeof input !== "object") {
    throw new RangeError("A route trip is required.");
  }
  const data = input as Record<string, unknown>;
  const origin = parseCoordinate(data.origin);
  const destination = parseCoordinate(data.destination);
  if (origin.latitude === destination.latitude &&
    origin.longitude === destination.longitude) {
    throw new RangeError("Origin and destination must differ.");
  }
  const rawTime = data.departureTime;
  const zonedTime = new RegExp(
    String.raw`^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}` +
    String.raw`(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$`,
  );
  if (typeof rawTime !== "string" ||
    !zonedTime.test(rawTime)) {
    throw new RangeError("Departure time needs an ISO time zone.");
  }
  const departureTime = new Date(rawTime);
  if (!Number.isFinite(departureTime.getTime())) {
    throw new RangeError("Invalid departure time.");
  }
  return {origin, destination, departureTime};
}

function parseCoordinate(value: unknown): GeoPoint {
  if (!value || typeof value !== "object") {
    throw new RangeError("Invalid route coordinate.");
  }
  const data = value as Record<string, unknown>;
  if (typeof data.lat !== "number" || typeof data.lng !== "number") {
    throw new RangeError("Invalid route coordinate.");
  }
  const point = {latitude: data.lat, longitude: data.lng};
  validateGeoPoint(point);
  return point;
}
