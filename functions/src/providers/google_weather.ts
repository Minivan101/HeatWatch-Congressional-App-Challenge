import {GeoPoint, validateGeoPoint} from "../shade/geometry";
import {WeatherObservation} from "../weather/heat_guard";

export function buildCurrentConditionsUrl(
  location: GeoPoint, apiKey: string,
): string {
  validateGeoPoint(location);
  if (!apiKey.trim()) throw new RangeError("Missing Weather API key.");
  const url = new URL(
    "https://weather.googleapis.com/v1/currentConditions:lookup");
  url.searchParams.set("location.latitude", String(location.latitude));
  url.searchParams.set("location.longitude", String(location.longitude));
  url.searchParams.set("unitsSystem", "METRIC");
  url.searchParams.set("key", apiKey);
  return url.toString();
}

export function parseCurrentConditionsResponse(payload: unknown): {
  observation: WeatherObservation; observedAt: Date;
} {
  if (!payload || typeof payload !== "object") {
    throw new TypeError("Invalid weather response.");
  }
  const data = payload as Record<string, unknown>;
  const temperature = data.temperature as Record<string, unknown> | undefined;
  const feelsLike = data.feelsLikeTemperature as
    Record<string, unknown> | undefined;
  const observedAt = new Date(String(data.currentTime));
  if (temperature?.unit !== "CELSIUS" ||
    feelsLike?.unit !== "CELSIUS" ||
    typeof temperature.degrees !== "number" ||
    !Number.isFinite(temperature.degrees) ||
    typeof feelsLike.degrees !== "number" ||
    !Number.isFinite(feelsLike.degrees) ||
    typeof data.relativeHumidity !== "number" ||
    !Number.isInteger(data.relativeHumidity) ||
    data.relativeHumidity < 0 || data.relativeHumidity > 100 ||
    typeof data.uvIndex !== "number" ||
    !Number.isInteger(data.uvIndex) || data.uvIndex < 0 ||
    !Number.isFinite(observedAt.getTime())) {
    throw new TypeError("Weather response is missing current measurements.");
  }
  return {
    observation: {
      temperatureC: temperature.degrees,
      feelsLikeC: feelsLike.degrees,
      humidityPercent: data.relativeHumidity,
      uvIndex: data.uvIndex,
    },
    observedAt,
  };
}
