import {ShadeRouteProviders} from "../shade/calculate_route";
import {buildWalkingRoutesRequest} from "./google_routes";
import {buildTimeZoneUrl} from "./google_timezone";

export function createGoogleShadeRouteProviders(
  apiKey: string,
  fetcher: typeof fetch = fetch,
): ShadeRouteProviders {
  if (!apiKey.trim()) throw new RangeError("A server API key is required.");
  return {
    getWalkingRoutes: async ({origin, destination}) => {
      const request = buildWalkingRoutesRequest(origin, destination, apiKey);
      const response = await fetcher(request.url, {
        method: request.method,
        headers: request.headers,
        body: JSON.stringify(request.body),
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) {
        throw new Error(`Routes provider failed (${response.status}).`);
      }
      return response.json();
    },
    getTimeZone: async (location, at) => {
      const url = buildTimeZoneUrl(location, at, apiKey);
      const response = await fetcher(url, {
        signal: AbortSignal.timeout(10000),
      });
      if (!response.ok) {
        throw new Error(`Time Zone provider failed (${response.status}).`);
      }
      return response.json();
    },
  };
}
