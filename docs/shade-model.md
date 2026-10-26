# Shade model

HeatWatch compares returned walking routes using the departure time, walking duration, sun position, buildings and tree heights. Fastest route and Most shade combine into Best route when they overlap by at least 90% in both directions, within 10 metres.

## Data

Buildings and estimated heights come from [Microsoft Global ML Building Footprints](https://github.com/microsoft/GlobalMLBuildingFootprints). Tree heights come from [Meta/WRI CHMv2](https://registry.opendata.aws/dataforgood-fb-forestsv2/). Dates, bounds, licenses, processing details and file hashes are in `data/shade/las_vegas/manifest.json`.

There are 441 building tiles and 441 canopy tiles. The app loads tiles as needed. Missing heights and masked canopy cells stay unknown. Older OSM data is kept for separate views and tests.

## Calculation

The calculator samples points along the route and updates the sun position as the trip progresses. At each point, it checks buildings and canopy toward the sun. Each sample becomes building shade, canopy shade, unknown, no predicted shade or night. Building and tree shade are not counted twice.

The normal route screen calculates shade locally after loading the walking route. New map tiles, searches and routes need internet. The packaged data does not include a complete offline walking network.

## Limits

Heights are estimates. Tree imagery may be old, small trees can be missed, and the model simplifies canopy shape and light passing through leaves. It leaves out terrain and detailed roofs. Mapped routes may differ from the sidewalk someone actually uses.

The app compares the routes it receives; it does not check every possible path. File hashes check data integrity, not real shade accuracy. We have not measured a shade-accuracy percentage, cooling effect or UV protection.

[Data sources](third-party-sources.md)
