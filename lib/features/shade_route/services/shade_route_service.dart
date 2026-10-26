import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/models/coordinates.dart';

enum ShadeRouteFailureKind {
  invalidTrip,
  noRoutes,
  outsideBuildingCoverage,
  unavailable,
  invalidResponse,
}

class ShadeRouteFailure implements Exception {
  const ShadeRouteFailure(this.kind);

  final ShadeRouteFailureKind kind;
}

class ShadeRouteTrip {
  const ShadeRouteTrip({
    required this.origin,
    required this.destination,
    required this.departureTime,
  });

  final Coordinates origin;
  final Coordinates destination;
  final DateTime departureTime;

  factory ShadeRouteTrip.fromDemoAsset(Map<String, dynamic> data) {
    final origin = data['origin'] as Map<String, dynamic>;
    final destination = data['destination'] as Map<String, dynamic>;
    return ShadeRouteTrip(
      origin: Coordinates(
        latitude: (origin['latitude'] as num).toDouble(),
        longitude: (origin['longitude'] as num).toDouble(),
      ),
      destination: Coordinates(
        latitude: (destination['latitude'] as num).toDouble(),
        longitude: (destination['longitude'] as num).toDouble(),
      ),
      departureTime: DateTime.parse(data['departureTime'] as String),
    );
  }

  Map<String, dynamic> toCallableData() {
    bool valid(Coordinates point) =>
        point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude.abs() <= 90 &&
        point.longitude.abs() <= 180;
    if (!valid(origin) ||
        !valid(destination) ||
        (origin.latitude == destination.latitude &&
            origin.longitude == destination.longitude)) {
      throw const FormatException('Invalid shade route trip');
    }
    return {
      'origin': {'lat': origin.latitude, 'lng': origin.longitude},
      'destination': {
        'lat': destination.latitude,
        'lng': destination.longitude,
      },
      'departureTime': departureTime.toUtc().toIso8601String(),
    };
  }
}

class ShadeRouteService {
  const ShadeRouteService({this.functions});

  final FirebaseFunctions? functions;

  Future<Map<String, dynamic>> getLiveRoutes(ShadeRouteTrip trip) async {
    late final Map<String, dynamic> request;
    try {
      request = trip.toCallableData();
    } on FormatException {
      throw const ShadeRouteFailure(ShadeRouteFailureKind.invalidTrip);
    }
    try {
      final result = await (functions ?? FirebaseFunctions.instance)
          .httpsCallable('getShadeRoutes')
          .call<Map<String, dynamic>>(request);
      final data = result.data;
      if (data['sampleOnly'] != false ||
          data['routeSource'] != 'Google Routes API walking candidates' ||
          data['timeZoneId'] is! String ||
          data['routes'] is! List) {
        throw const ShadeRouteFailure(ShadeRouteFailureKind.invalidResponse);
      }
      if ((data['routes'] as List).isEmpty) {
        throw const ShadeRouteFailure(ShadeRouteFailureKind.noRoutes);
      }
      return data;
    } on FirebaseFunctionsException catch (error) {
      final kind = switch (error.code) {
        'invalid-argument' => ShadeRouteFailureKind.invalidTrip,
        'not-found' => ShadeRouteFailureKind.noRoutes,
        'failed-precondition' => ShadeRouteFailureKind.outsideBuildingCoverage,
        _ => ShadeRouteFailureKind.unavailable,
      };
      throw ShadeRouteFailure(kind);
    }
  }

  Future<Map<String, dynamic>> getDemoRoutes(ShadeRouteTrip trip) async {
    late final Map<String, dynamic> request;
    try {
      request = trip.toCallableData();
    } on FormatException {
      throw const ShadeRouteFailure(ShadeRouteFailureKind.invalidTrip);
    }
    try {
      final result = await (functions ?? FirebaseFunctions.instance)
          .httpsCallable('getShadeRouteDemo')
          .call<Map<String, dynamic>>(request);
      final data = result.data;
      if (data['sampleOnly'] != true || data['routes'] is! List) {
        throw const ShadeRouteFailure(ShadeRouteFailureKind.invalidResponse);
      }
      if ((data['routes'] as List).isEmpty) {
        throw const ShadeRouteFailure(ShadeRouteFailureKind.noRoutes);
      }
      return data;
    } on FirebaseFunctionsException catch (error) {
      final kind = switch (error.code) {
        'invalid-argument' => ShadeRouteFailureKind.invalidTrip,
        'not-found' => ShadeRouteFailureKind.noRoutes,
        'failed-precondition' => ShadeRouteFailureKind.outsideBuildingCoverage,
        _ => ShadeRouteFailureKind.unavailable,
      };
      throw ShadeRouteFailure(kind);
    }
  }
}
