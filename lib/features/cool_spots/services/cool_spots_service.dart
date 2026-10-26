import 'package:cloud_functions/cloud_functions.dart';

import '../models/cool_spots_contract.dart';

class CoolSpotsService {
  const CoolSpotsService({this.functions});

  final FirebaseFunctions? functions;

  Future<Map<String, dynamic>> getLocalExample(
    Map<String, dynamic> location,
  ) async {
    final result = await (functions ?? FirebaseFunctions.instance)
        .httpsCallable('getCoolSpotsDemo')
        .call<Map<String, dynamic>>({
          'location': location,
          'radiusMeters': 1500,
        });
    final data = result.data;
    CoolSpotsContract.fictionalPlaces(data);
    final reference = data['referenceLocation'];
    final places = data['indoorPlaces'];
    if (data['sampleOnly'] != true ||
        data['checkedAt'] is! String ||
        reference is! Map ||
        reference['latitude'] != location['latitude'] ||
        reference['longitude'] != location['longitude'] ||
        places is! List ||
        places.any(
          (place) => place is! Map || place['source'] != 'FICTIONAL_FIXTURE',
        )) {
      throw const FormatException('Local Cool Spots example is incomplete');
    }
    return data;
  }

  Future<Map<String, dynamic>> getLocalCenters() async {
    final result = await (functions ?? FirebaseFunctions.instance)
        .httpsCallable('getLocalCoolingCenters')
        .call<Map<String, dynamic>>();
    return CoolSpotsContract.localCenters(result.data);
  }
}
