import {readFile} from "node:fs/promises";
import {dirname, join} from "node:path";
import {RouteGeometry, ShadeBuilding} from "./estimate";
import {decodePolyline} from "./geometry";
import {MAX_SHADOW_LENGTH_METERS} from "./shadows";

export type GeoBounds = {
  south: number;
  west: number;
  north: number;
  east: number;
};

type PreparedBuilding = ShadeBuilding & {osmId: string};
type TileRecord = {key: string; file: string; buildingCount: number};
type PreparedManifest = {
  coverageBounds: GeoBounds;
  coverageGaps: {reason: string; bounds: GeoBounds | null}[];
  tileSizeDegrees: number;
  tiles: TileRecord[];
};

const EARTH_RADIUS_METERS = 6_371_000;

export function expandedRouteBounds(
  routes: RouteGeometry[],
  marginMeters = MAX_SHADOW_LENGTH_METERS,
): GeoBounds {
  if (routes.length === 0 || !Number.isFinite(marginMeters) ||
    marginMeters < 0) {
    throw new RangeError("Invalid route bounds request.");
  }
  const points = routes.flatMap((route) =>
    decodePolyline(route.encodedPolyline));
  if (points.length < 2) throw new RangeError("Route has too few vertices.");
  const south = Math.min(...points.map((point) => point.latitude));
  const west = Math.min(...points.map((point) => point.longitude));
  const north = Math.max(...points.map((point) => point.latitude));
  const east = Math.max(...points.map((point) => point.longitude));
  const latitudeMargin = marginMeters / EARTH_RADIUS_METERS * 180 / Math.PI;
  const edgeLatitude = Math.max(Math.abs(south), Math.abs(north));
  const cosine = Math.cos(edgeLatitude * Math.PI / 180);
  if (cosine <= 0.01) {
    throw new RangeError("Local tile bounds do not support polar routes.");
  }
  const longitudeMargin = latitudeMargin / cosine;
  const bounds = {
    south: south - latitudeMargin,
    west: west - longitudeMargin,
    north: north + latitudeMargin,
    east: east + longitudeMargin,
  };
  validateBounds(bounds);
  return bounds;
}

export async function loadPreparedBuildings(
  manifestPath: string,
  queryBounds: GeoBounds,
): Promise<ShadeBuilding[]> {
  const manifest = JSON.parse(await readFile(manifestPath, "utf8")) as
    PreparedManifest;
  validateBounds(queryBounds);
  validateBounds(manifest.coverageBounds);
  const coverage = manifest.coverageBounds;
  if (queryBounds.south < coverage.south ||
    queryBounds.west < coverage.west ||
    queryBounds.north > coverage.north ||
    queryBounds.east > coverage.east) {
    throw new RangeError("Building dataset does not cover the route area.");
  }
  if (!Array.isArray(manifest.coverageGaps) ||
    manifest.coverageGaps.some((gap) => !gap.bounds ||
      (gap.bounds.south <= queryBounds.north &&
        gap.bounds.north >= queryBounds.south &&
        gap.bounds.west <= queryBounds.east &&
        gap.bounds.east >= queryBounds.west))) {
    throw new RangeError(
      "Building dataset has incomplete shapes in the route area.");
  }
  const step = manifest.tileSizeDegrees;
  if (!Number.isFinite(step) || step <= 0) {
    throw new RangeError("Invalid building tile size.");
  }
  const wanted = new Set<string>();
  for (let lat = Math.floor(queryBounds.south / step);
    lat <= Math.floor(queryBounds.north / step); lat++) {
    for (let lon = Math.floor(queryBounds.west / step);
      lon <= Math.floor(queryBounds.east / step); lon++) {
      wanted.add(`${lat}_${lon}`);
    }
  }

  const result = new Map<string, PreparedBuilding>();
  for (const tile of manifest.tiles) {
    if (!wanted.has(tile.key)) continue;
    const data = JSON.parse(await readFile(
      join(dirname(manifestPath), tile.file), "utf8")) as
      {buildings: PreparedBuilding[]};
    for (const building of data.buildings) {
      if (footprintIntersects(building.footprint, queryBounds)) {
        result.set(building.osmId, building);
      }
    }
  }
  return [...result.values()];
}

function validateBounds(bounds: GeoBounds): void {
  if (!bounds || !Number.isFinite(bounds.south) ||
    !Number.isFinite(bounds.west) || !Number.isFinite(bounds.north) ||
    !Number.isFinite(bounds.east) || bounds.south >= bounds.north ||
    bounds.west >= bounds.east || bounds.south < -90 || bounds.north > 90 ||
    bounds.west < -180 || bounds.east > 180) {
    throw new RangeError("Invalid geographic bounds.");
  }
}

function footprintIntersects(
  footprint: ShadeBuilding["footprint"],
  bounds: GeoBounds,
): boolean {
  const latitudes = footprint.map((point) => point.latitude);
  const longitudes = footprint.map((point) => point.longitude);
  return Math.min(...latitudes) <= bounds.north &&
    Math.max(...latitudes) >= bounds.south &&
    Math.min(...longitudes) <= bounds.east &&
    Math.max(...longitudes) >= bounds.west;
}
