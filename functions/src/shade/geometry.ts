
export type GeoPoint = {latitude: number; longitude: number};

export type MetricPoint = {eastMeters: number; northMeters: number};

const EARTH_RADIUS_METERS = 6_371_000;
const DEG = Math.PI / 180;

export function projectLocal(
  point: GeoPoint,
  reference: GeoPoint,
): MetricPoint {
  validateGeoPoint(point);
  validateGeoPoint(reference);
  return {
    eastMeters: EARTH_RADIUS_METERS *
      Math.cos(reference.latitude * DEG) *
      (point.longitude - reference.longitude) * DEG,
    northMeters: EARTH_RADIUS_METERS *
      (point.latitude - reference.latitude) * DEG,
  };
}

export function validateGeoPoint(point: GeoPoint): void {
  if (!point || !Number.isFinite(point.latitude) ||
    !Number.isFinite(point.longitude) ||
    Math.abs(point.latitude) > 90 || Math.abs(point.longitude) > 180) {
    throw new RangeError("Invalid geographic coordinate.");
  }
}

export function decodePolyline(encoded: string): GeoPoint[] {
  if (!encoded) throw new RangeError("Polyline cannot be empty.");
  const points: GeoPoint[] = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;

  function readDelta(): number {
    let result = 0;
    let shift = 0;
    let value: number;
    do {
      if (index >= encoded.length || shift > 30) {
        throw new RangeError("Invalid encoded polyline.");
      }
      value = encoded.charCodeAt(index++) - 63;
      if (value < 0 || value > 63) {
        throw new RangeError("Invalid encoded polyline.");
      }
      result += (value & 0x1f) * 2 ** shift;
      if (value >= 0x20) shift += 5;
    } while (value >= 0x20);
    return result & 1 ? -(result + 1) / 2 : result / 2;
  }

  while (index < encoded.length) {
    latitude += readDelta();
    longitude += readDelta();
    const point = {
      latitude: latitude / 1e5,
      longitude: longitude / 1e5,
    };
    validateGeoPoint(point);
    points.push(point);
  }
  return points;
}
