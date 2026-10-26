import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/services/location_service.dart';

class FakeLocationClient implements LocationClient {
  FakeLocationClient({
    this.enabled = true,
    this.permission = LocationPermission.whileInUse,
    this.requestedPermission = LocationPermission.whileInUse,
  });

  bool enabled;
  LocationPermission permission;
  LocationPermission requestedPermission;
  bool requested = false;
  bool readPosition = false;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requested = true;
    return requestedPermission;
  }

  @override
  Future<Coordinates> getCurrentPosition() async {
    readPosition = true;
    return const Coordinates(latitude: 34.0522, longitude: -118.2437);
  }
}

void main() {
  test('foreground walking requests frequent updates and no Apple background access', () {
    final android = LocationService.walkingSettings(
      TargetPlatform.android,
    ) as AndroidSettings;
    expect(android.distanceFilter, 0);
    expect(android.intervalDuration, const Duration(seconds: 2));
    expect(android.foregroundNotificationConfig, isNull);
    final ios =
        LocationService.walkingSettings(TargetPlatform.iOS) as AppleSettings;
    expect(ios.distanceFilter, 0);
    expect(ios.pauseLocationUpdatesAutomatically, false);
    expect(ios.allowBackgroundLocationUpdates, false);
  });
  test('reads location when permission is already granted', () async {
    final client = FakeLocationClient();
    final result = await LocationService(client: client).getCurrentPosition();

    expect(result.latitude, 34.0522);
    expect(client.requested, isFalse);
    expect(client.readPosition, isTrue);
  });

  test('requests permission only when it is denied', () async {
    final client = FakeLocationClient(permission: LocationPermission.denied);
    await LocationService(client: client).getCurrentPosition();
    expect(client.requested, isTrue);
    expect(client.readPosition, isTrue);
  });

  test(
    'silent refresh reports missing permission without opening an OS prompt',
    () async {
      final client = FakeLocationClient(permission: LocationPermission.denied);
      await expectLater(
        LocationService(client: client)
            .getCurrentPosition(requestPermission: false),
        throwsA(isA<LocationAccessException>()),
      );
      expect(client.requested, isFalse);
      expect(client.readPosition, isFalse);
    },
  );

  test('reports a denied permission without reading location', () async {
    final client = FakeLocationClient(
      permission: LocationPermission.denied,
      requestedPermission: LocationPermission.denied,
    );
    await expectLater(
      LocationService(client: client).getCurrentPosition(),
      throwsA(
        isA<LocationAccessException>().having(
          (error) => error.problem,
          'problem',
          LocationProblem.denied,
        ),
      ),
    );
    expect(client.readPosition, isFalse);
  });

  test('reports permanently denied permission', () async {
    final client = FakeLocationClient(
      permission: LocationPermission.deniedForever,
    );
    await expectLater(
      LocationService(client: client).getCurrentPosition(),
      throwsA(
        isA<LocationAccessException>().having(
          (error) => error.problem,
          'problem',
          LocationProblem.deniedForever,
        ),
      ),
    );
    expect(client.requested, isFalse);
    expect(client.readPosition, isFalse);
  });

  test('reports location services disabled', () async {
    final client = FakeLocationClient(enabled: false);
    await expectLater(
      LocationService(client: client).getCurrentPosition(),
      throwsA(
        isA<LocationAccessException>().having(
          (error) => error.problem,
          'problem',
          LocationProblem.servicesDisabled,
        ),
      ),
    );
    expect(client.requested, isFalse);
    expect(client.readPosition, isFalse);
  });
}
