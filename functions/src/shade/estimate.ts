import {GeoPoint, decodePolyline, projectLocal} from "./geometry";
import {inferBuildingHeight} from "./buildings";
import {rankRoutes, shadeFractionFromSegments} from "./scoring";
import {sampleRoute} from "./route_sampling";
import {pointInSweptShadow} from "./shadow_geometry";
import {shadowVector} from "./shadows";
import {solarPosition} from "./solar";
import {BuildingIndex} from "./building_index";

export type RouteGeometry = {
  id: string;
  durationSeconds: number;
  encodedPolyline: string;
};

export type ShadeBuilding = {
  footprint: GeoPoint[];
  tags: Record<string, string>;
};

export type EstimatedRoute = {
  id: string;
  durationSeconds: number;
  distanceMeters: number;
  shadeFraction: number | null;
  daylightDistanceMeters: number;
  sampleCount: number;
};

export type ShadeEstimate = {
  routes: EstimatedRoute[];
  choices: {fastest: string; balanced: string | null; mostShade: string | null};
  estimated: true;
};

export function estimateShadeRoutes(
  routes: RouteGeometry[],
  buildings: ShadeBuilding[],
  departureTime: Date,
  utcOffsetSeconds: number,
  useIndex = buildings.length >= 100,
): ShadeEstimate {
  if (routes.length === 0 || !Number.isFinite(departureTime.getTime()) ||
    !Number.isFinite(utcOffsetSeconds) ||
    Math.abs(utcOffsetSeconds) > 14 * 3600) {
    throw new RangeError("Invalid shade-estimation input.");
  }

  const estimated = routes.map((route) => estimateOneRoute(
    route, buildings, departureTime, utcOffsetSeconds, useIndex,
  ));
  const dayRoutes = estimated.filter((route) => route.shadeFraction !== null);
  const allNight = dayRoutes.length === 0;
  const ranked = rankRoutes(estimated.map((route) => ({
    id: route.id,
    durationSeconds: route.durationSeconds,
    shadeFraction: route.shadeFraction ?? 0,
  })), {nightMode: allNight});
  return {
    routes: estimated,
    choices: {
      fastest: ranked.fastest.id,
      balanced: ranked.balanced?.id ?? null,
      mostShade: ranked.mostShade?.id ?? null,
    },
    estimated: true,
  };
}

function estimateOneRoute(
  route: RouteGeometry,
  buildings: ShadeBuilding[],
  departureTime: Date,
  utcOffsetSeconds: number,
  useIndex: boolean,
): EstimatedRoute {
  if (!route.id || !Number.isFinite(route.durationSeconds) ||
    route.durationSeconds <= 0) {
    throw new RangeError("Invalid walking route.");
  }
  const vertices = decodePolyline(route.encodedPolyline);
  const sampled = sampleRoute(vertices);
  const reference = vertices[0];
  const projectedBuildings = buildings.map((building) => {
    if (building.footprint.length < 3) {
      throw new RangeError("Building footprint requires three vertices.");
    }
    return {
      footprint: building.footprint.map((point) =>
        projectLocal(point, reference)),
      heightMeters: inferBuildingHeight(building.tags).heightMeters,
    };
  });
  const index = useIndex ? new BuildingIndex(
    projectedBuildings.map((building) => building.footprint)) : null;

  const segments: {distanceMeters: number; shaded: boolean}[] = [];
  for (const sample of sampled.samples) {
    const fraction = sample.cumulativeDistanceMeters /
      sampled.totalDistanceMeters;
    const at = new Date(departureTime.getTime() +
      route.durationSeconds * fraction * 1000);
    const sun = solarPosition(at, sample.coordinate.latitude,
      sample.coordinate.longitude, utcOffsetSeconds);
    if (sun.elevationDeg <= 0) continue;

    const point = projectLocal(sample.coordinate, reference);
    const candidates = index?.candidates(point) ??
      projectedBuildings.map((_, index) => index);
    const shaded = candidates.some((candidate) => {
      const building = projectedBuildings[candidate];
      const shadow = shadowVector(building.heightMeters,
        sun.elevationDeg, sun.azimuthDeg);
      return shadow !== null && pointInSweptShadow(
        point, building.footprint, shadow);
    });
    segments.push({
      distanceMeters: sample.representedDistanceMeters,
      shaded,
    });
  }
  const daylightDistanceMeters = segments.reduce((sum, segment) =>
    sum + segment.distanceMeters, 0);
  return {
    id: route.id,
    durationSeconds: route.durationSeconds,
    distanceMeters: sampled.totalDistanceMeters,
    shadeFraction: segments.length > 0 ?
      shadeFractionFromSegments(segments) : null,
    daylightDistanceMeters,
    sampleCount: sampled.samples.length,
  };
}
