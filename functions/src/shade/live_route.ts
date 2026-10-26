import {calculateShadeRoute, ShadeRouteRequest} from "./calculate_route";
import {createGoogleShadeRouteProviders} from "../providers/google_http";

export async function calculateLiveShadeRoute(
  request: ShadeRouteRequest,
  buildingManifestPath: string,
  serverApiKey: string,
  fetcher: typeof fetch = fetch,
) {
  const result = await calculateShadeRoute(request,
    createGoogleShadeRouteProviders(serverApiKey, fetcher),
    buildingManifestPath);
  return {
    ...result,
    sampleOnly: false,
    routeSource: "Google Routes API walking candidates" as const,
  };
}
