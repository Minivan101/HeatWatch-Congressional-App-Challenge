import {GeoPoint, validateGeoPoint} from "../shade/geometry";
import {OfficialHeatAlert, hasExplicitOffset} from "../weather/heat_guard";

export function buildPublicAlertsUrl(
  location: GeoPoint, apiKey: string,
): string {
  validateGeoPoint(location);
  if (!apiKey.trim()) throw new RangeError("Missing Weather API key.");
  const url = new URL("https://weather.googleapis.com/v1/publicAlerts:lookup");
  url.searchParams.set("location.latitude", String(location.latitude));
  url.searchParams.set("location.longitude", String(location.longitude));
  url.searchParams.set("pageSize", "20");
  url.searchParams.set("key", apiKey);
  return url.toString();
}

export type ParsedHeatAlerts = {
  alerts: OfficialHeatAlert[];
  alertsChecked: true;
};

export function parsePublicAlertsResponse(payload: unknown): ParsedHeatAlerts {
  if (!payload || typeof payload !== "object") {
    throw new TypeError("Invalid public-alert response.");
  }
  const data = payload as Record<string, unknown>;
  if (!Array.isArray(data.weatherAlerts) ||
    (typeof data.nextPageToken === "string" && data.nextPageToken)) {
    throw new TypeError("Public-alert check is incomplete.");
  }
  const alerts: OfficialHeatAlert[] = [];
  for (const value of data.weatherAlerts) {
    if (!value || typeof value !== "object") {
      throw new TypeError("Invalid public-alert record.");
    }
    const alert = value as Record<string, unknown>;
    if (alert.eventType !== "HEAT") continue;
    const title = (alert.alertTitle as Record<string, unknown> | undefined)
      ?.text;
    const source = alert.dataSource as Record<string, unknown> | undefined;
    const expiry = alert.expirationTime;
    const severity = alert.severity;
    if (typeof title !== "string" || !title.trim() ||
      typeof source?.name !== "string" || !source.name.trim() ||
      typeof source.authorityUri !== "string" ||
      !source.authorityUri.startsWith("https://") ||
      typeof expiry !== "string" ||
      !hasExplicitOffset(expiry) ||
      typeof severity !== "string") {
      throw new TypeError("Heat alert is missing source or expiry.");
    }
    const severityMap: Record<string, OfficialHeatAlert["severity"]> = {
      SEVERITY_UNKNOWN: "unknown",
      MINOR: "minor",
      MODERATE: "moderate",
      SEVERE: "severe",
      EXTREME: "extreme",
    };
    if (!severityMap[severity]) {
      throw new TypeError("Unknown heat-alert severity.");
    }
    alerts.push({
      title: title.trim(),
      severity: severityMap[severity],
      source: source.name.trim(),
      sourceUrl: source.authorityUri,
      expiresAt: new Date(expiry).toISOString(),
    });
  }
  return {alerts, alertsChecked: true};
}
