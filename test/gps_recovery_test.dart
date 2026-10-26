import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/core/location/app_location.dart';
import 'package:heatwatch/core/models/coordinates.dart';
import 'package:heatwatch/core/services/location_service.dart';
import 'package:heatwatch/core/settings/app_settings.dart';

const vegas = Coordinates(latitude: 36.19, longitude: -115.28);

class RestartGPS extends LocationService {
  final streams = <StreamController<WalkingLocationFix>>[];
  int prompts = 0;
  @override
  Future<Coordinates> getCurrentPosition({
    bool requestPermission = true,
  }) async {
    if (requestPermission) prompts++;
    return vegas;
  }

  @override
  Stream<WalkingLocationFix> watchPosition() {
    final stream = StreamController<WalkingLocationFix>.broadcast(sync: true);
    streams.add(stream);
    return stream.stream;
  }
}

void main() {
  testWidgets('permission removal is terminal and never retries silently', (
    t,
  ) async {
    final settings = AppSettings(read: () async => null, write: (_) async {});
    final gps = RestartGPS();
    final location = AppLocation(settings, service: gps);
    await location.choose(LocationChoice.session);
    location.startTracking();
    gps.streams.last.addError(
      const LocationAccessException(LocationProblem.deniedForever),
    );
    await t.pump(const Duration(seconds: 30));
    expect(location.tracking, false);
    expect(location.error, isNotNull);
    expect(gps.streams, hasLength(1));
    expect(gps.prompts, 1);
    location.dispose();
    settings.dispose();
    for (final stream in gps.streams) {
      await stream.close();
    }
  });

  testWidgets(
    'temporary GPS errors reconnect without stopping or asking again',
    (t) async {
      final settings = AppSettings(read: () async => null, write: (_) async {});
      final gps = RestartGPS();
      final location = AppLocation(settings, service: gps);
      await location.choose(LocationChoice.session);
      location.startTracking();
      gps.streams.last.addError(StateError('temporary native failure'));
      await t.pump();
      expect(location.tracking, true);
      expect(location.error, isNull);
      await t.pump(const Duration(seconds: 5));
      expect(gps.streams, hasLength(2));
      gps.streams.last.add(
        WalkingLocationFix(vegas, DateTime.now(), accuracy: 5),
      );
      expect(location.fix, isNotNull);
      expect(gps.prompts, 1);
      location.dispose();
      settings.dispose();
      for (final stream in gps.streams) {
        await stream.close();
      }
    },
  );
  testWidgets('retry ends on opt-out and waits while backgrounded', (t) async {
    final settings = AppSettings(read: () async => null, write: (_) async {});
    final gps = RestartGPS();
    final location = AppLocation(settings, service: gps);
    await location.choose(LocationChoice.session);
    location.startTracking();
    await gps.streams.last.close();
    await t.pump();
    location.didChangeAppLifecycleState(AppLifecycleState.paused);
    await t.pump(const Duration(seconds: 30));
    expect(gps.streams, hasLength(1));
    location.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(gps.streams, hasLength(2));
    gps.streams.last.addError(StateError('temporary native failure'));
    await t.pump();
    await location.choose(LocationChoice.never);
    await t.pump(const Duration(seconds: 30));
    expect(gps.streams, hasLength(2));
    expect(location.tracking, false);
    location.dispose();
    settings.dispose();
    for (final stream in gps.streams) {
      await stream.close();
    }
  });
}
