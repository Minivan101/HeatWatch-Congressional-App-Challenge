import {MetricPoint} from "./geometry";
import {ShadowVector} from "./shadows";

const EPSILON = 1e-8;

// building shade
export function pointInSweptShadow(
  point: MetricPoint,
  footprint: MetricPoint[],
  shadow: ShadowVector,
): boolean {
  validateMetricPoint(point);
  if (footprint.length < 3 || !Number.isFinite(shadow.eastMeters) ||
    !Number.isFinite(shadow.northMeters)) {
    throw new RangeError("Invalid building shadow geometry.");
  }
  footprint.forEach(validateMetricPoint);
  if (pointInPolygon(point, footprint)) return true;
  const shifted = footprint.map((vertex) => ({
    eastMeters: vertex.eastMeters + shadow.eastMeters,
    northMeters: vertex.northMeters + shadow.northMeters,
  }));
  if (pointInPolygon(point, shifted)) return true;
  for (let index = 0; index < footprint.length; index++) {
    const next = (index + 1) % footprint.length;
    if (pointInPolygon(point, [
      footprint[index], footprint[next], shifted[next], shifted[index],
    ])) return true;
  }
  return false;
}

function pointInPolygon(point: MetricPoint, polygon: MetricPoint[]): boolean {
  let inside = false;
  for (let index = 0, previous = polygon.length - 1;
    index < polygon.length; previous = index++) {
    const a = polygon[previous];
    const b = polygon[index];
    if (onSegment(point, a, b)) return true;
    const crosses = (a.northMeters > point.northMeters) !==
      (b.northMeters > point.northMeters);
    if (crosses) {
      const eastAtCrossing = a.eastMeters +
        (point.northMeters - a.northMeters) *
        (b.eastMeters - a.eastMeters) /
        (b.northMeters - a.northMeters);
      if (point.eastMeters < eastAtCrossing) inside = !inside;
    }
  }
  return inside;
}

function onSegment(
  point: MetricPoint, a: MetricPoint, b: MetricPoint,
): boolean {
  const cross = (point.eastMeters - a.eastMeters) *
    (b.northMeters - a.northMeters) -
    (point.northMeters - a.northMeters) *
    (b.eastMeters - a.eastMeters);
  if (Math.abs(cross) > EPSILON) return false;
  return point.eastMeters >= Math.min(a.eastMeters, b.eastMeters) - EPSILON &&
    point.eastMeters <= Math.max(a.eastMeters, b.eastMeters) + EPSILON &&
    point.northMeters >= Math.min(a.northMeters, b.northMeters) - EPSILON &&
    point.northMeters <= Math.max(a.northMeters, b.northMeters) + EPSILON;
}

function validateMetricPoint(point: MetricPoint): void {
  if (!point || !Number.isFinite(point.eastMeters) ||
    !Number.isFinite(point.northMeters)) {
    throw new RangeError("Invalid local metric point.");
  }
}
