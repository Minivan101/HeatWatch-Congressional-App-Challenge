'prepare building tiles'

import argparse
import hashlib
import json
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path

TILE_DEGREES = 0.002
HEIGHT_RE = re.compile(r"^(\d+(?:\.\d+)?)\s*m?$", re.IGNORECASE)

def estimate_height(tags):

    raw_height = tags.get("height", "").strip()
    match = HEIGHT_RE.fullmatch(raw_height)
    if match:
        height = float(match.group(1))
        if math.isfinite(height) and height > 0:
            return height, "high", "height"

    levels = tags.get("building:levels", "").strip()
    if levels.isdigit() and int(levels) > 0:
        return int(levels) * 3.0, "medium", "building:levels"

    return 9.0, "low", "assumed"

def extract_buildings(root):

    nodes = {
        node.attrib["id"]: {
            "latitude": float(node.attrib["lat"]),
            "longitude": float(node.attrib["lon"]),
        }
        for node in root.findall("node")
    }
    ways = {way.attrib["id"]: way for way in root.findall("way")}
    buildings = []
    gaps = []
    skipped = {"open": 0, "missing_nodes": 0, "invalid": 0}
    consumed = set()

    def gap_for(refs, reason):
        points = [nodes[ref] for ref in refs if ref in nodes]
        if not points:
            gaps.append({"reason": reason, "bounds": None})
            return
        gaps.append({"reason": reason, "bounds": {
            "south": min(p["latitude"] for p in points),
            "north": max(p["latitude"] for p in points),
            "west": min(p["longitude"] for p in points),
            "east": max(p["longitude"] for p in points),
        }})

    def append_building(osm_id, refs, tags):
        footprint = [nodes[ref] for ref in refs[:-1]]
        height, confidence, source = estimate_height(tags)
        buildings.append({
            "osmId": osm_id,
            "footprint": footprint,
            "heightMeters": height,
            "heightConfidence": confidence,
            "heightSource": source,
            "tags": {key: value for key, value in tags.items()
                     if key in ("height", "building:levels")},
        })

    def join_rings(chains):

        rings = []
        pending = [list(chain) for chain in chains]
        while pending:
            ring = pending.pop(0)
            while ring[0] != ring[-1]:
                match = next((i for i, chain in enumerate(pending)
                              if chain[0] in (ring[0], ring[-1]) or
                              chain[-1] in (ring[0], ring[-1])), None)
                if match is None:
                    return None
                chain = pending.pop(match)
                if chain[0] == ring[-1]:
                    ring += chain[1:]
                elif chain[-1] == ring[-1]:
                    ring += list(reversed(chain[:-1]))
                elif chain[-1] == ring[0]:
                    ring = chain[:-1] + ring
                else:
                    ring = list(reversed(chain[1:])) + ring
            rings.append(ring)
        return rings

    skipped_relations = 0
    for relation in root.findall("relation"):
        tags = {tag.attrib["k"]: tag.attrib["v"]
                for tag in relation.findall("tag")}
        if tags.get("type") != "multipolygon" or \
                tags.get("building") in (None, "no"):
            continue
        members = [m for m in relation.findall("member")
                   if m.attrib.get("type") == "way"]
        refs = [m.attrib["ref"] for m in members]
        known_refs = [nd.attrib["ref"] for ref in refs if ref in ways
                      for nd in ways[ref].findall("nd")]
        if any(m.attrib.get("role") == "inner" for m in members) or \
                not members or any(ref not in ways for ref in refs):
            skipped_relations += 1
            gap_for(known_refs, "unsupported building relation")
            continue
        chains = [[nd.attrib["ref"] for nd in ways[ref].findall("nd")]
                  for ref in refs]
        rings = join_rings(chains)
        if rings is None or any(len(set(ring[:-1])) < 3 or
                                any(ref not in nodes for ref in ring)
                                for ring in rings):
            skipped_relations += 1
            gap_for(known_refs, "incomplete building relation")
            continue
        for index, ring in enumerate(rings):
            append_building(f"relation/{relation.attrib['id']}/{index}",
                            ring, tags)
        consumed.update(refs)

    for way in root.findall("way"):
        if way.attrib["id"] in consumed:
            continue
        tags = {tag.attrib["k"]: tag.attrib["v"] for tag in way.findall("tag")}
        if "building" not in tags or tags["building"] == "no":
            continue
        refs = [node.attrib["ref"] for node in way.findall("nd")]
        if len(refs) < 4 or refs[0] != refs[-1]:
            skipped["open"] += 1
            gap_for(refs, "open building way")
            continue
        if any(ref not in nodes for ref in refs):
            skipped["missing_nodes"] += 1
            gap_for(refs, "building way missing nodes")
            continue
        if len(set(refs[:-1])) < 3:
            skipped["invalid"] += 1
            gap_for(refs, "invalid building way")
            continue
        append_building(f"way/{way.attrib['id']}", refs, tags)
    buildings.sort(key=lambda item: item["osmId"])
    return buildings, skipped, skipped_relations, gaps

def tile_buildings(buildings):

    tiles = {}
    for building in buildings:
        points = building["footprint"]
        south = min(point["latitude"] for point in points)
        north = max(point["latitude"] for point in points)
        west = min(point["longitude"] for point in points)
        east = max(point["longitude"] for point in points)
        lat_start = math.floor(south / TILE_DEGREES)
        lat_end = math.floor(north / TILE_DEGREES)
        lon_start = math.floor(west / TILE_DEGREES)
        lon_end = math.floor(east / TILE_DEGREES)
        if (lat_end - lat_start + 1) * (lon_end - lon_start + 1) > 100:
            raise ValueError(f"Building spans too many tiles: {building['osmId']}")
        for lat_index in range(lat_start, lat_end + 1):
            for lon_index in range(lon_start, lon_end + 1):
                key = f"{lat_index}_{lon_index}"
                tiles.setdefault(key, []).append(building)
    return tiles

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

def prepare(source, output_dir, preview_manifest, downloaded_at, clip=None):
    source_bytes = source.read_bytes()
    root = ET.fromstring(source_bytes)
    bounds = root.find("bounds")
    if bounds is None:
        raise ValueError("OSM export is missing coverage bounds")
    coverage = {
        "south": float(bounds.attrib["minlat"]),
        "west": float(bounds.attrib["minlon"]),
        "north": float(bounds.attrib["maxlat"]),
        "east": float(bounds.attrib["maxlon"]),
    }
    buildings, skipped, skipped_relations, gaps = extract_buildings(root)
    if not buildings:
        raise ValueError("OSM export contains no usable building footprints")
    if clip is not None:
        west, south, east, north = clip
        if not (coverage['west'] <= west < east <= coverage['east'] and
                coverage['south'] <= south < north <= coverage['north']):
            raise ValueError("Clip bounds must lie within the saved OSM export")
        coverage = {"west": west, "south": south, "east": east, "north": north}
        def intersects(points):
            return (min(p['latitude'] for p in points) <= north and
                    max(p['latitude'] for p in points) >= south and
                    min(p['longitude'] for p in points) <= east and
                    max(p['longitude'] for p in points) >= west)
        buildings = [b for b in buildings if intersects(b['footprint'])]
        gaps = [g for g in gaps if g['bounds'] is None or
                (g['bounds']['south'] <= north and g['bounds']['north'] >= south and
                 g['bounds']['west'] <= east and g['bounds']['east'] >= west)]
        if not buildings:
            raise ValueError("Clip bounds contain no usable buildings")
    tiles = tile_buildings(buildings)
    tile_records = []
    for key, members in sorted(tiles.items()):
        name = f"tile_{key}.json"
        write_json(output_dir / name, {
            "buildings": members,
            "tileKey": key,
        })
        tile_records.append({
            "key": key,
            "file": name,
            "buildingCount": len(members),
        })

    confidence = {
        level: sum(building["heightConfidence"] == level
                   for building in buildings)
        for level in ("high", "medium", "low")
    }
    manifest = {
        "source": "OpenStreetMap",
        "attribution": "© OpenStreetMap contributors",
        "licenseUrl": "https://www.openstreetmap.org/copyright",
        "downloadedAt": downloaded_at,
        "coverageBounds": coverage,
        "sourceSha256": hashlib.sha256(source_bytes).hexdigest(),
        "tileSizeDegrees": TILE_DEGREES,
        "buildingCount": len(buildings),
        "heightConfidenceCounts": confidence,
        "skippedWays": skipped,
        "skippedBuildingRelations": skipped_relations,
        "coverageGaps": gaps,
        "tiles": tile_records,
    }
    write_json(output_dir / "manifest.json", manifest)
    write_json(preview_manifest, manifest)
    return manifest

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("preview_manifest", type=Path)
    parser.add_argument("--downloaded-at", required=True)
    parser.add_argument("--clip-bounds", type=float, nargs=4,
                        metavar=("WEST", "SOUTH", "EAST", "NORTH"))
    args = parser.parse_args()
    result = prepare(args.source, args.output_dir,
                     args.preview_manifest, args.downloaded_at, args.clip_bounds)
    print(f"Prepared {result['buildingCount']} buildings "
          f"in {len(result['tiles'])} tiles")
