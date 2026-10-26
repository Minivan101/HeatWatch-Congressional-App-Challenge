import {OfficialCoolingCenter, createCoolSpotsSnapshot} from "./cool_spots";
import {GeoPoint, validateGeoPoint} from "../shade/geometry";

export type CuratedCenterDataset = {
  datasetId: string;
  region: string;
  sourceAgency: string;
  sourceUrl: string;
  sourceCheckedAt: string;
  timeZoneId: string;
  sampleReference: {label: string; location: GeoPoint};
  note: string;
  centers: OfficialCoolingCenter[];
};

export function parseCuratedCenterDataset(
  payload: unknown,
): CuratedCenterDataset {
  if (!payload || typeof payload !== "object") {
    throw new TypeError("Invalid cooling-center dataset.");
  }
  const data = payload as CuratedCenterDataset;
  if (!data.datasetId?.trim() || !data.region?.trim() ||
    !data.sourceAgency?.trim() ||
    !data.sourceUrl?.startsWith("https://") ||
    !data.timeZoneId?.trim() || !data.note?.trim() ||
    !data.sampleReference?.label?.trim() ||
    !Array.isArray(data.centers) || data.centers.length === 0 ||
    !Number.isFinite(new Date(data.sourceCheckedAt).getTime())) {
    throw new TypeError("Cooling-center dataset lacks source metadata.");
  }
  validateGeoPoint(data.sampleReference.location);
  const ids = new Set<string>();
  for (const center of data.centers) {
    if (center.sourceAgency !== data.sourceAgency ||
      center.sourceUrl !== data.sourceUrl ||
      ids.has(center.id)) {
      throw new TypeError("Cooling-center source or ID mismatch.");
    }
    ids.add(center.id);
  }

  createCoolSpotsSnapshot(data.centers, [], new Date(data.sourceCheckedAt));
  return data;
}
