import {GeoPoint, MetricPoint, projectLocal} from "./geometry";

export type RouteSample = {
  coordinate: GeoPoint;
  representedDistanceMeters: number;
  cumulativeDistanceMeters: number;
};

export type SampledRoute = {
  totalDistanceMeters: number;
  samples: RouteSample[];
};

export function sampleRoute(
  vertices: GeoPoint[],
  spacingMeters = 10,
): SampledRoute {
  if (vertices.length < 2 || !Number.isFinite(spacingMeters) ||
    spacingMeters <= 0) {
    throw new RangeError("Route needs two vertices and positive spacing.");
  }
  const reference = vertices[0];
  const projected = vertices.map((point) => projectLocal(point, reference));
  const lengths: number[] = [];
  let total = 0;
  for (let index = 1; index < projected.length; index++) {
    const length = distance(projected[index - 1], projected[index]);
    lengths.push(length);
    total += length;
  }
  if (total <= 0) throw new RangeError("Route distance must be positive.");

  const samples: RouteSample[] = [];
  let segmentIndex = 0;
  let segmentStart = 0;
  for (let start = 0; start < total; start += spacingMeters) {
    const end = Math.min(start + spacingMeters, total);
    const midpoint = (start + end) / 2;
    while (segmentIndex < lengths.length - 1 &&
      midpoint > segmentStart + lengths[segmentIndex]) {
      segmentStart += lengths[segmentIndex++];
    }
    const segmentLength = lengths[segmentIndex];
    const fraction = segmentLength > 0 ?
      (midpoint - segmentStart) / segmentLength : 0;
    const from = vertices[segmentIndex];
    const to = vertices[segmentIndex + 1];
    samples.push({
      coordinate: {
        latitude: from.latitude + (to.latitude - from.latitude) * fraction,
        longitude: from.longitude +
          (to.longitude - from.longitude) * fraction,
      },
      representedDistanceMeters: end - start,
      cumulativeDistanceMeters: midpoint,
    });
  }
  return {totalDistanceMeters: total, samples};
}

function distance(from: MetricPoint, to: MetricPoint): number {
  return Math.hypot(
    to.eastMeters - from.eastMeters,
    to.northMeters - from.northMeters,
  );
}
