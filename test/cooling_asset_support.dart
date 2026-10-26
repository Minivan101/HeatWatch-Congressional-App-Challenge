import 'dart:convert';
import 'dart:io';

import 'package:heatwatch/features/cool_spots/models/unofficial_cooling_directory.dart';

Future<Map<String, dynamic>> loadTestDiscoveryAssets() async => {
  'points': (jsonDecode(
    File('assets/cool_spots/zip_points.json').readAsStringSync(),
  ) as Map)['points'],
  'photos': jsonDecode(
    File('assets/cool_spots/photos.json').readAsStringSync(),
  ),
};
Future<UnofficialCoolingDirectory> loadTestCommunityDirectory() async =>
    UnofficialCoolingDirectory.parse(
      jsonDecode(
        File('data/cooling_centers/unofficial_directory.json')
            .readAsStringSync(),
      ),
    );
