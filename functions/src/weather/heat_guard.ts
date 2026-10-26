import {uvGuidance} from "./guidance";

export type WeatherObservation = {
  temperatureC: number;
  feelsLikeC: number;
  humidityPercent: number;
  uvIndex: number;
};

export type OfficialHeatAlert = {
  title: string;
  severity: "unknown" | "minor" | "moderate" | "severe" | "extreme";
  source: string;
  sourceUrl: string;
  expiresAt: string;
};

export type HeatGuardSnapshot = {
  current: WeatherObservation;
  alerts: OfficialHeatAlert[];
  alertsChecked: boolean;
  guidance: string[];
  fetchedAt: string;
};

export function hasExplicitOffset(value: string): boolean {
  return /(?:Z|[+-]\d{2}:\d{2})$/i.test(value) &&
    Number.isFinite(new Date(value).getTime());
}

export function createHeatGuardSnapshot(
  current: WeatherObservation,
  alerts: OfficialHeatAlert[],
  fetchedAt: Date,
  alertsChecked: boolean,
): HeatGuardSnapshot {
  if (!Number.isFinite(fetchedAt.getTime()) ||
    !Number.isFinite(current.temperatureC) ||
    !Number.isFinite(current.feelsLikeC) ||
    !Number.isFinite(current.humidityPercent) ||
    current.humidityPercent < 0 || current.humidityPercent > 100 ||
    !Number.isFinite(current.uvIndex) || current.uvIndex < 0 ||
    (!alertsChecked && alerts.length > 0)) {
    throw new RangeError("Invalid Heat Guard input.");
  }
  const activeAlerts = alerts.filter((alert) => {
    const expiresAt = new Date(alert.expiresAt);
    if (!alert.title.trim() || !alert.source.trim() ||
      !alert.sourceUrl.startsWith("https://") ||
      !hasExplicitOffset(alert.expiresAt) ||
      !Number.isFinite(expiresAt.getTime())) {
      throw new RangeError("Invalid official alert.");
    }
    return expiresAt.getTime() > fetchedAt.getTime();
  });
  const guidance = [uvGuidance(current.uvIndex).message];
  if (activeAlerts.length > 0) {
    guidance.unshift(
      "Follow the linked official alert and local instructions.");
  }
  return {
    current,
    alerts: activeAlerts,
    alertsChecked,
    guidance,
    fetchedAt: fetchedAt.toISOString(),
  };
}
