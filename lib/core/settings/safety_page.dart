import '../../features/heat_guard/presentation/weather_overview.dart';

import 'package:flutter/material.dart';

import '../../features/heat_guard/presentation/weather_guidance.dart';

class SafetyPage extends StatelessWidget {
  const SafetyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Warnings & safety'),
      actions: const [CurrentTemperatureDisplay()],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text(
          'Plan with care',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        Text(
          'HeatWatch supports planning. It cannot guarantee a safe walk or replace official instructions or medical advice. Follow current NWS alerts and local conditions.',
        ),
        ListTile(
          leading: Icon(Icons.ac_unit),
          title: Text('Cooling locations'),
          subtitle: Text(
            'Official locations follow county activation periods and facility hours. Unofficial places are community alternatives: outdoor fountains supply drinking water, while indoor venues offer cooling during opening hours. Fountain flow and venue access can change; check before travel. Food or drinks may cost extra. Map points may mark a fountain, trailhead or building center rather than an entrance.',
          ),
        ),
        ListTile(
          leading: Icon(Icons.route),
          title: Text('Routes & shade'),
          subtitle: Text(
            'Shade estimates may differ from actual conditions and have not been validated against on-site measurements. Walking routes use OpenStreetMap footpaths and public street geometry. Where sidewalks are not separately mapped, street routes assume walking access; a drawn line does not confirm a sidewalk, crosswalk or safe passage. Highways and recorded pedestrian restrictions are excluded. Street centerlines also make shade estimates less precise than actual sidewalk positions. Check sidewalks, crossings, gates and closures. Shade is predicted from Microsoft building-height estimates and Meta/WRI canopy heights at changing trip times. Canopy is approximated as opaque columns and may overstate protection, especially beneath sparse trees or near sunrise/sunset. Data can be old, incomplete or misplaced; terrain and detailed roofs are excluded. Shadows are capped at 250 m. Orange means no shade predicted by this model, not verified sunshine. Unknown sections remain unknown; when small enough for comparison they contribute to a conservative upper estimate of sun exposure. No calculated shade value means data is unavailable, not zero shade. Night has zero direct-sun exposure, so fully nighttime trips use the fastest walking option. When daylight data is incomplete, HeatWatch keeps the fastest route instead of guessing a shade advantage. The daylight cutoff is approximate near sunrise and sunset.',
          ),
        ),
        ListTile(
          leading: Icon(Icons.sunny),
          title: Text('Weather & UV'),
          subtitle: Text(
            'Forecasts model a grid area and can differ from your exact surroundings. Saved readings have a retrieval date; refresh before travel. No returned alerts is not a guarantee of safety. Shade does not establish UV protection or a temperature reduction.',
          ),
        ),
        ListTile(
          leading: Icon(Icons.location_on),
          title: Text('Location & privacy'),
          subtitle: Text(
            'Location choice is a HeatWatch preference, separate from device permission. Every opening uses foreground location only. Session-only choice is remembered, but location access ends on the next cold launch. Re-enable it in Settings. Never disables automatic location. Short route calculations send the trip area to Overpass; longer trips or unavailable short-route map transfers send requested start, destination and intermediate points to the free FOSSGIS walking service, which logs requests. GPS following is local, but rerouting sends the new start point. Place searches go to Photon; foreground weather updates send the selected point to Open-Meteo and NWS. Weather starts automatically for the saved Las Vegas area, or your position if location is enabled. These services have their own policies.',
          ),
        ),
        Text(
          'Source details and measured data remain available in feature reports. Actual weather alerts and unavailable readings are shown when relevant. Notifications remain off.',
        ),
        SourceLink(
          label: 'Official county cooling directory',
          url: 'https://www.clarkcountynv.gov/government/departments/fire/cooling-stations',
        ),
        SourceLink(
          label: 'Pedestrian map API policy',
          url: 'https://dev.overpass-api.de/overpass-doc/en/preface/commons.html',
        ),
        SourceLink(
          label: 'Long walking service policy',
          url: 'https://routing.openstreetmap.de/about.html',
        ),
        SourceLink(
          label: 'Place search policy',
          url: 'https://photon.komoot.io/',
        ),
        SourceLink(
          label: 'OpenStreetMap data licence',
          url: 'https://www.openstreetmap.org/copyright',
        ),
      ],
    ),
  );
}
