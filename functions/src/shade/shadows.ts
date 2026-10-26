
export type ShadowVector = {
  eastMeters: number;
  northMeters: number;
  lengthMeters: number;
  capped: boolean;
};

const DEG = Math.PI / 180;
export const MAX_SHADOW_LENGTH_METERS = 250;

export function shadowVector(
  heightMeters: number,
  solarElevationDeg: number,
  solarAzimuthDeg: number,
  maxLengthMeters = MAX_SHADOW_LENGTH_METERS,
): ShadowVector | null {
  if (
    !Number.isFinite(heightMeters) || heightMeters < 0 ||
    !Number.isFinite(solarElevationDeg) ||
      solarElevationDeg < -90 || solarElevationDeg > 90 ||
    !Number.isFinite(solarAzimuthDeg) ||
    !Number.isFinite(maxLengthMeters) || maxLengthMeters <= 0
  ) {
    throw new RangeError("Invalid shadow input.");
  }
  if (solarElevationDeg <= 0) return null;

  const geometricLength = heightMeters /
    Math.tan(solarElevationDeg * DEG);
  const capped = geometricLength > maxLengthMeters;
  const lengthMeters = Math.min(geometricLength, maxLengthMeters);
  const shadowAzimuth = (solarAzimuthDeg + 180) * DEG;
  return {
    eastMeters: lengthMeters * Math.sin(shadowAzimuth),
    northMeters: lengthMeters * Math.cos(shadowAzimuth),
    lengthMeters,
    capped,
  };
}
