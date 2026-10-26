import {GeoPoint} from "../shade/geometry";

export function buildTimeZoneUrl(
  location: GeoPoint, when: Date, apiKey: string,
): string {
  if (!Number.isFinite(location.latitude) ||
    location.latitude < -90 || location.latitude > 90 ||
    !Number.isFinite(location.longitude) ||
    location.longitude < -180 || location.longitude > 180 ||
    !Number.isFinite(when.getTime()) || !apiKey.trim()) {
    throw new RangeError("Invalid time zone request.");
  }
  const url = new URL("https://maps.googleapis.com/maps/api/timezone/json");
  url.searchParams.set("location",
    `${location.latitude},${location.longitude}`);
  url.searchParams.set("timestamp", String(Math.floor(when.getTime() / 1000)));
  url.searchParams.set("key", apiKey);
  return url.toString();
}

export type RouteTimeZone = {timeZoneId: string; utcOffsetSeconds: number};

export function parseTimeZoneResponse(payload: unknown): RouteTimeZone {
  if (!payload || typeof payload !== "object") {
    throw new TypeError("Invalid time zone response.");
  }
  const response = payload as Record<string, unknown>;
  if (response.status !== "OK") {
    throw new Error(`Time Zone API status: ${String(response.status)}`);
  }
  const raw = response.rawOffset;
  const dst = response.dstOffset;
  const id = response.timeZoneId;
  if (typeof raw !== "number" || !Number.isFinite(raw) ||
    typeof dst !== "number" || !Number.isFinite(dst) ||
    typeof id !== "string" || !id || Math.abs(raw + dst) > 14 * 3600) {
    throw new TypeError("Time zone response is missing a valid offset.");
  }
  return {timeZoneId: id, utcOffsetSeconds: raw + dst};
}
