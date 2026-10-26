
export type SolarPosition = {
  elevationDeg: number;
  azimuthDeg: number;
};

const DEG = Math.PI / 180;
const DAY_MS = 86_400_000;

function normalize(value: number, period: number): number {
  return ((value % period) + period) % period;
}

export function solarPosition(
  utcDate: Date,
  latitudeDeg: number,
  longitudeDeg: number,
  utcOffsetSeconds: number,
): SolarPosition {
  if (
    !Number.isFinite(utcDate.getTime()) ||
    !Number.isFinite(latitudeDeg) || latitudeDeg < -90 || latitudeDeg > 90 ||
    !Number.isFinite(longitudeDeg) ||
      longitudeDeg < -180 || longitudeDeg > 180 ||
    !Number.isFinite(utcOffsetSeconds) || Math.abs(utcOffsetSeconds) > 14 * 3600
  ) {
    throw new RangeError("Invalid solar-position input.");
  }

  const year = utcDate.getUTCFullYear();
  const dayOfYear = Math.floor(
    (Date.UTC(year, utcDate.getUTCMonth(), utcDate.getUTCDate()) -
      Date.UTC(year, 0, 1)) / DAY_MS,
  ) + 1;
  const yearDays = (Date.UTC(year + 1, 0, 1) - Date.UTC(year, 0, 1)) / DAY_MS;
  const hour = utcDate.getUTCHours() + utcDate.getUTCMinutes() / 60 +
    utcDate.getUTCSeconds() / 3600;
  const gamma = (2 * Math.PI / yearDays) * (dayOfYear - 1 + (hour - 12) / 24);
  const equationOfTime = 229.18 * (
    0.000075 +
    0.001868 * Math.cos(gamma) -
    0.032077 * Math.sin(gamma) -
    0.014615 * Math.cos(2 * gamma) -
    0.040849 * Math.sin(2 * gamma)
  );
  const declination =
    0.006918 -
    0.399912 * Math.cos(gamma) +
    0.070257 * Math.sin(gamma) -
    0.006758 * Math.cos(2 * gamma) +
    0.000907 * Math.sin(2 * gamma) -
    0.002697 * Math.cos(3 * gamma) +
    0.00148 * Math.sin(3 * gamma);
  const trueSolarMinutes = normalize(
    hour * 60 + equationOfTime + 4 * longitudeDeg,
    1440,
  );
  const hourAngle = (trueSolarMinutes / 4 - 180) * DEG;
  const latitude = latitudeDeg * DEG;
  const sinElevation =
    Math.sin(latitude) * Math.sin(declination) +
    Math.cos(latitude) * Math.cos(declination) * Math.cos(hourAngle);
  const elevation = Math.asin(Math.max(-1, Math.min(1, sinElevation)));
  const azimuth = Math.atan2(
    Math.sin(hourAngle),
    Math.cos(hourAngle) * Math.sin(latitude) -
      Math.tan(declination) * Math.cos(latitude),
  );

  return {
    elevationDeg: elevation / DEG,
    azimuthDeg: normalize(azimuth / DEG + 180, 360),
  };
}
