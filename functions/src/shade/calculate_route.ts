import {
  GeoPoint, decodePolyline, projectLocal, validateGeoPoint,
} from "./geometry";
import {estimateShadeRoutes, ShadeEstimate} from "./estimate";
import {expandedRouteBounds, loadPreparedBuildings} from "./prepared_buildings";
import {parseWalkingRoutesResponse} from "../providers/google_routes";
import {parseTimeZoneResponse} from "../providers/google_timezone";

export type ShadeRouteRequest = {
  origin: GeoPoint;
  destination: GeoPoint;
  departureTime: Date;
};

export type ShadeRouteProviders = {
  getWalkingRoutes: (request: ShadeRouteRequest) => Promise<unknown>;
  getTimeZone: (location: GeoPoint, at: Date) => Promise<unknown>;
};

export type CalculatedShadeRoute = ShadeEstimate & {
  routes: (ShadeEstimate["routes"][number] & {
    encodedPolyline: string;
    estimatedShadedMeters: number | null;
  })[];
  buildingCount: number;
  calculatedAt: string;
  dataSource: "OpenStreetMap building footprints";
  timeZoneId: string;
  confidence: "prototype";
  walkingCaution: string;
};

export async function calculateShadeRoute(
  request: ShadeRouteRequest,
  providers: ShadeRouteProviders,
  buildingManifestPath: string,
): Promise<CalculatedShadeRoute> {
  validateGeoPoint(request.origin);
  validateGeoPoint(request.destination);
  if (!Number.isFinite(request.departureTime.getTime()) ||
    !buildingManifestPath ||
    (request.origin.latitude === request.destination.latitude &&
      request.origin.longitude === request.destination.longitude)) {
    throw new RangeError("Invalid shade route request.");
  }

  const response = await providers.getWalkingRoutes(request);
  const routes = parseWalkingRoutesResponse(response);
  for (const route of routes) {
    const vertices = decodePolyline(route.encodedPolyline);
    if (vertices.length < 2 ||
      distanceMeters(vertices[0], request.origin) > 100 ||
      distanceMeters(vertices[vertices.length - 1],
        request.destination) > 100) {
      throw new RangeError("Returned route does not match the requested trip.");
    }
  }
  const bounds = expandedRouteBounds(routes);
  const buildings = await loadPreparedBuildings(buildingManifestPath, bounds);

  const firstRoute = decodePolyline(routes[0].encodedPolyline);
  const routePoint = firstRoute[Math.floor(firstRoute.length / 2)];
  const timeZoneResponse = await providers.getTimeZone(
    routePoint, request.departureTime);
  const zone = parseTimeZoneResponse(timeZoneResponse);
  const estimate = estimateShadeRoutes(
    routes, buildings, request.departureTime, zone.utcOffsetSeconds);
  const geometryById = new Map(routes.map((route) =>
    [route.id, route.encodedPolyline]));
  return {
    ...estimate,
    routes: estimate.routes.map((route) => ({
      ...route,
      encodedPolyline: geometryById.get(route.id)!,
      estimatedShadedMeters: route.shadeFraction === null ? null :
        route.daylightDistanceMeters * route.shadeFraction,
    })),
    buildingCount: buildings.length,
    calculatedAt: new Date().toISOString(),
    dataSource: "OpenStreetMap building footprints",
    timeZoneId: zone.timeZoneId,
    confidence: "prototype",
    walkingCaution: "Walking routes can miss sidewalks or paths. " +
      "Check real-world conditions.",
  };
}

function distanceMeters(a: GeoPoint, b: GeoPoint): number {
  const projected = projectLocal(a, b);
  return Math.hypot(projected.eastMeters, projected.northMeters);
}
