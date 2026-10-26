import {GeoPoint, validateGeoPoint} from "../shade/geometry";
import {centerDateStatus, localCalendarDate} from "./local_date";

export type OfficialCoolingCenter = {
  id: string;
  name: string;
  location: GeoPoint;
  address: string;
  category: "OFFICIAL_COOLING_CENTER";
  sourceAgency: string;
  sourceUrl: string;
  locationSourceUrl?: string;
  validFrom: string;
  validUntil: string;
  lastVerifiedAt: string;
  hours: string;
};

export type NearbyIndoorPlace = {
  placeId: string;
  name: string;
  location: GeoPoint;
  address: string;
  category: "INDOOR_PLACE";
  openNow: boolean | null;
  distanceMeters: number;
  source: "GOOGLE_PLACES" | "FICTIONAL_FIXTURE";
};

export type CoolSpotsSnapshot = {
  officialCenters: OfficialCoolingCenter[];
  indoorPlaces: NearbyIndoorPlace[];
  checkedAt: string;
};

export function createCoolSpotsSnapshot(
  centers: OfficialCoolingCenter[],
  businesses: NearbyIndoorPlace[],
  checkedAt: Date,
  timeZoneId = "UTC",
): CoolSpotsSnapshot {
  if (!Number.isFinite(checkedAt.getTime())) {
    throw new RangeError("Invalid Cool Spots timestamp.");
  }
  const day = localCalendarDate(checkedAt, timeZoneId);
  const officialCenters = centers.filter((center) => {
    validateGeoPoint(center.location);
    if (center.category !== "OFFICIAL_COOLING_CENTER" ||
      !center.id.trim() || !center.name.trim() ||
      !center.address.trim() || !center.sourceAgency.trim() ||
      !center.sourceUrl.startsWith("https://") ||
      (center.locationSourceUrl !== undefined &&
        !center.locationSourceUrl.startsWith("https://")) ||
      !validDate(center.validFrom) || !validDate(center.validUntil) ||
      center.validFrom > center.validUntil ||
      !Number.isFinite(new Date(center.lastVerifiedAt).getTime()) ||
      !center.hours.trim()) {
      throw new RangeError("Invalid official cooling center record.");
    }
    return centerDateStatus(center.validFrom, center.validUntil, day) ===
      "date-listed";
  });
  for (const business of businesses) {
    validateGeoPoint(business.location);
    if (business.category !== "INDOOR_PLACE" ||
      (business.source !== "GOOGLE_PLACES" &&
        business.source !== "FICTIONAL_FIXTURE") ||
      !business.placeId.trim() || !business.name.trim() ||
      !business.address.trim() ||
      !Number.isFinite(business.distanceMeters) ||
      business.distanceMeters < 0 ||
      (business.openNow !== null &&
        typeof business.openNow !== "boolean")) {
      throw new RangeError("Invalid indoor place record.");
    }
  }
  return {
    officialCenters,
    indoorPlaces: businesses,
    checkedAt: checkedAt.toISOString(),
  };
}

function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}
