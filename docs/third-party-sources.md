# Data sources and rights

These are the sources used in the project. This list does not mean every item is cleared for public release. Keep the source details and notices bundled with the data.

| Material | Source records | Release notes |
| --- | --- | --- |
| Buildings and heights | `data/shade/las_vegas/manifest.json`: Microsoft Global ML Building Footprints, CDLA Permissive 2.0, URLs and hashes | Keep license text and notices. Note local processing. |
| Tree heights | Same manifest: Meta/WRI CHMv2, CC BY 4.0, Vantor imagery, dates and processing | Keep attribution, license link and modification notice. Check requirements for derived tiles. |
| OSM maps, search and routes | `data/osm/`, building manifests and route records in `docs/research/` | Check ODbL requirements for extracts and derived databases. Keep OpenStreetMap and provider credits. |
| Official cooling places | `data/cooling_centers/official_directory.json` and county, GIS, library and operator records in `data/cooling_centers/` | Keep dates, revisions, URLs and source claims. Check snapshot redistribution rights separately from factual records. |
| Community cooling places | `data/cooling_centers/unofficial_directory.json` and `unofficial_sources/snapshot-manifest.json` in the same folder | Keep source evidence and dates. Distinguish these places from designated cooling stations. Check snapshot redistribution rights. |
| Weather and UV | Open-Meteo responses and `data/weather/research/manifest.json` | Keep attribution. Check current free-service terms and data licenses before release or wider use. |
| Official alerts | NWS responses in `data/weather/research/` | Keep original sources, times and NWS credits. Check request and use policies. |
| Solar test values | `test/fixtures/solar_reference.json`: pinned pvlib 0.15.0 NREL SPA outputs, source hash and benchmark | The producer code is external. Its BSD license applies if that code is redistributed. SPA code is not embedded in the app. |
| Dependencies | `pubspec.lock`, `functions/package-lock.json` and installed packages | Review licenses for the exact release dependencies. They do not all share one license. |

License labels in manifests record the source information we have. Public-release clearance still needs a separate review.
