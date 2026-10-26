
export type ShadeSegment = {distanceMeters: number; shaded: boolean};

export type CandidateRoute = {
  id: string;
  durationSeconds: number;
  shadeFraction: number;
};

export type RankedRoutes = {
  fastest: CandidateRoute;
  balanced: CandidateRoute | null;
  mostShade: CandidateRoute | null;
};

export function shadeFractionFromSegments(segments: ShadeSegment[]): number {
  let total = 0;
  let shaded = 0;
  for (const segment of segments) {
    if (!Number.isFinite(segment.distanceMeters) ||
        segment.distanceMeters < 0) {
      throw new RangeError("Segment distances must be nonnegative.");
    }
    total += segment.distanceMeters;
    if (segment.shaded) shaded += segment.distanceMeters;
  }
  if (total <= 0) {
    throw new RangeError("At least one positive-distance segment is required.");
  }
  return shaded / total;
}

export function balancedScore(
  shadeFraction: number,
  durationSeconds: number,
  fastestSeconds: number,
  shadeWeight = 0.6,
): number {
  if (
    !Number.isFinite(shadeFraction) ||
      shadeFraction < 0 || shadeFraction > 1 ||
    !Number.isFinite(durationSeconds) || durationSeconds <= 0 ||
    !Number.isFinite(fastestSeconds) || fastestSeconds <= 0 ||
    !Number.isFinite(shadeWeight) || shadeWeight < 0 || shadeWeight > 1
  ) {
    throw new RangeError("Invalid route score input.");
  }
  return shadeWeight * shadeFraction +
    (1 - shadeWeight) * fastestSeconds / durationSeconds;
}

export function rankRoutes(
  candidates: CandidateRoute[],
  options: {
    nightMode?: boolean;
    maxDetourRatio?: number;
    shadeWeight?: number;
  } = {},
): RankedRoutes {
  const {nightMode = false, maxDetourRatio = 1.5, shadeWeight = 0.6} = options;
  if (candidates.length === 0 ||
      !Number.isFinite(maxDetourRatio) || maxDetourRatio < 1 ||
      !Number.isFinite(shadeWeight) || shadeWeight < 0 || shadeWeight > 1) {
    throw new RangeError("Invalid route ranking input.");
  }
  const ids = new Set<string>();
  for (const route of candidates) {
    if (!route.id || ids.has(route.id)) {
      throw new RangeError("Route IDs must be unique and nonempty.");
    }
    ids.add(route.id);
    balancedScore(route.shadeFraction, route.durationSeconds,
      route.durationSeconds, shadeWeight);
  }
  const byDuration = [...candidates].sort((a, b) =>
    a.durationSeconds - b.durationSeconds || a.id.localeCompare(b.id));
  const fastest = byDuration[0];
  if (nightMode) return {fastest, balanced: null, mostShade: null};

  const eligible = byDuration.filter((route) =>
    route.durationSeconds <= fastest.durationSeconds * maxDetourRatio);
  const byShade = [...eligible].sort((a, b) =>
    b.shadeFraction - a.shadeFraction ||
    a.durationSeconds - b.durationSeconds || a.id.localeCompare(b.id));
  const byBalance = [...eligible].sort((a, b) =>
    balancedScore(b.shadeFraction, b.durationSeconds,
      fastest.durationSeconds, shadeWeight) -
    balancedScore(a.shadeFraction, a.durationSeconds,
      fastest.durationSeconds, shadeWeight) ||
    a.durationSeconds - b.durationSeconds || a.id.localeCompare(b.id));
  return {fastest, balanced: byBalance[0], mostShade: byShade[0]};
}
