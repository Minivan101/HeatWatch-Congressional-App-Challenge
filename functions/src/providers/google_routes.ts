import {GeoPoint} from "../shade/geometry";
import {RouteGeometry} from "../shade/estimate";

export const WALKING_ROUTE_FIELD_MASK =
  "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline";

export type JsonPostRequest = {
  url: string;
  method: "POST";
  headers: Record<string, string>;
  body: Record<string, unknown>;
};

function validPoint(point: GeoPoint): boolean {
  return Number.isFinite(point.latitude) &&
    point.latitude >= -90 && point.latitude <= 90 &&
    Number.isFinite(point.longitude) &&
    point.longitude >= -180 && point.longitude <= 180;
}

export function buildWalkingRoutesRequest(
  origin: GeoPoint, destination: GeoPoint, apiKey: string,
): JsonPostRequest {
  if (!validPoint(origin) || !validPoint(destination) ||
    (origin.latitude === destination.latitude &&
      origin.longitude === destination.longitude) ||
    !apiKey.trim()) {
    throw new RangeError("Invalid walking route request.");
  }
  return {
    url: "https://routes.googleapis.com/directions/v2:computeRoutes",
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": WALKING_ROUTE_FIELD_MASK,
    },
    body: {
      origin: {location: {latLng: origin}},
      destination: {location: {latLng: destination}},
      travelMode: "WALK",
      computeAlternativeRoutes: true,
      polylineEncoding: "ENCODED_POLYLINE",
      polylineQuality: "HIGH_QUALITY",
    },
  };
}

export function parseWalkingRoutesResponse(payload: unknown): RouteGeometry[] {
  if (!payload || typeof payload !== "object" ||
    !Array.isArray((payload as {routes?: unknown}).routes)) {
    throw new TypeError("Routes response has no routes array.");
  }
  const rawRoutes = (payload as {routes: unknown[]}).routes;
  if (rawRoutes.length === 0) {
    throw new RangeError("No walking routes were returned.");
  }
  const seen = new Set<string>();
  const routes: RouteGeometry[] = [];
  for (const raw of rawRoutes) {
    if (!raw || typeof raw !== "object") {
      throw new TypeError("Invalid walking route.");
    }
    const route = raw as Record<string, unknown>;
    const polyline = (route.polyline as {encodedPolyline?: unknown} | undefined)
      ?.encodedPolyline;
    const duration = route.duration;
    const distance = route.distanceMeters;
    const durationSeconds = typeof duration === "string" &&
      /^\d+(?:\.\d+)?s$/.test(duration) ? Number(duration.slice(0, -1)) : NaN;
    if (typeof polyline !== "string" || !polyline ||
      !Number.isFinite(durationSeconds) || durationSeconds <= 0 ||
      typeof distance !== "number" || !Number.isFinite(distance) ||
      distance <= 0) {
      throw new TypeError(
        "Walking route is missing geometry, time, or distance.");
    }
    if (seen.has(polyline)) continue;
    seen.add(polyline);
    routes.push({
      id: `route-${routes.length + 1}`,
      durationSeconds,
      encodedPolyline: polyline,
    });
  }
  return routes;
}
