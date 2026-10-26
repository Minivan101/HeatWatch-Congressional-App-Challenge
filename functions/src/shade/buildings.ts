
export type BuildingHeight = {
  heightMeters: number;
  confidence: "high" | "medium" | "low";
  source: "height" | "building:levels" | "assumed";
};

function parseMetricHeight(raw: string | undefined): number | null {
  if (!raw) return null;
  const match = raw.trim().match(/^(\d+(?:\.\d+)?)\s*(?:m)?$/i);
  if (!match) return null;
  const meters = Number(match[1]);
  return meters > 0 && Number.isFinite(meters) ? meters : null;
}

export function inferBuildingHeight(
  tags: Record<string, string>,
): BuildingHeight {
  const height = parseMetricHeight(tags.height);
  if (height !== null) {
    return {heightMeters: height, confidence: "high", source: "height"};
  }

  const levelsRaw = tags["building:levels"]?.trim();
  if (levelsRaw && /^\d+(?:\.\d+)?$/.test(levelsRaw)) {
    const levels = Number(levelsRaw);
    if (levels > 0 && Number.isFinite(levels)) {
      return {
        heightMeters: levels * 3,
        confidence: "medium",
        source: "building:levels",
      };
    }
  }
  return {heightMeters: 9, confidence: "low", source: "assumed"};
}
