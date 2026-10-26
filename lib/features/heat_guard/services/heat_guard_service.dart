import 'package:cloud_functions/cloud_functions.dart';

import '../models/heat_guard_contract.dart';

class HeatGuardService {
  const HeatGuardService({this.functions});

  final FirebaseFunctions? functions;

  Future<Map<String, dynamic>> getLocalExample() async {
    final result = await (functions ?? FirebaseFunctions.instance)
        .httpsCallable('getHeatGuardDemo')
        .call<Map<String, dynamic>>();
    return HeatGuardContract.localExample(result.data);
  }
}
