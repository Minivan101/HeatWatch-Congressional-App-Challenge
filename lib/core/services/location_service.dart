import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

import '../models/coordinates.dart';

class WalkingLocationFix {
  const WalkingLocationFix(
    this.point,
    this.at, {
    this.accuracy = 0,
    this.heading,
    this.speed = 0,
  });
  final Coordinates point;
  final DateTime at;
  final double accuracy, speed;
  final double? heading;
}

enum LocationProblem { servicesDisabled, denied, deniedForever }

class LocationAccessException implements Exception {
  const LocationAccessException(this.problem);

  final LocationProblem problem;

  String get message => switch (problem) {
    LocationProblem.servicesDisabled =>
      'Location services are off. Turn them on in Settings, then try again.',
    LocationProblem.denied =>
      'Location access was denied. You can try again when you are ready.',
    LocationProblem.deniedForever =>
      'Location access is off for HeatWatch. Enable it in device Settings.',
  };
}

abstract class LocationClient {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Coordinates> getCurrentPosition();
}

class GeolocatorLocationClient implements LocationClient {
  const GeolocatorLocationClient();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Coordinates> getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return Coordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}

class LocationService {
  const LocationService({this.client = const GeolocatorLocationClient()});

  final LocationClient client;

  static LocationSettings walkingSettings(TargetPlatform platform) {
    if (!kIsWeb && platform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 2),
      );
    }
    if (!kIsWeb &&
        (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS)) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 0,
    );
  }

  Stream<WalkingLocationFix> watchPosition() async* {
    if (!await client.isLocationServiceEnabled()) {
      throw const LocationAccessException(LocationProblem.servicesDisabled);
    }
    final permission = await client.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw LocationAccessException(
        permission == LocationPermission.deniedForever
            ? LocationProblem.deniedForever
            : LocationProblem.denied,
      );
    }
    await for (final p in Geolocator.getPositionStream(
      locationSettings: walkingSettings(defaultTargetPlatform),
    )) {
      yield WalkingLocationFix(
        Coordinates(latitude: p.latitude, longitude: p.longitude),
        p.timestamp,
        accuracy: p.accuracy,
        speed: p.speed,
        heading:
            p.heading.isFinite &&
                p.heading >= 0 &&
                p.heading < 360 &&
                p.headingAccuracy >= 0 &&
                p.headingAccuracy <= 30
            ? p.heading
            : null,
      );
    }
  }

  Future<Coordinates> getCurrentPosition({
    bool requestPermission = true,
  }) async {
    if (!await client.isLocationServiceEnabled()) {
      throw const LocationAccessException(LocationProblem.servicesDisabled);
    }

    var permission = await client.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await client.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationAccessException(LocationProblem.deniedForever);
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const LocationAccessException(LocationProblem.denied);
    }

    return client.getCurrentPosition();
  }
}
