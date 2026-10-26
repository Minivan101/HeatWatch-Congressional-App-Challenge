import 'dart:async';

import 'package:flutter/material.dart';

import '../models/coordinates.dart';
import '../services/location_service.dart';
import '../settings/app_settings.dart';

// foreground location
class AppLocation extends ChangeNotifier with WidgetsBindingObserver {
  AppLocation(this.settings, {this.service = const LocationService()}) {
    WidgetsBinding.instance.addObserver(this);
  }
  final AppSettings settings;
  final LocationService service;
  Coordinates? position;
  String? error;
  bool busy = false, _disposed = false;
  bool _sessionActive = false, _choiceDialogOpen = false;
  int _generation = 0, _trackingGeneration = 0;
  StreamSubscription<WalkingLocationFix>? _tracking;
  bool _trackingRequested = false, _foreground = true;
  WalkingLocationFix? fix;
  String? trackingError;
  Timer? _trackingRetry;
  int _retrySeconds = 5;
  bool get locationAllowed =>
      choice == LocationChoice.everyOpen ||
      choice == LocationChoice.session && _sessionActive;
  bool get tracking => _trackingRequested && _foreground && locationAllowed;

  void startTracking() {
    if (!locationAllowed || _disposed) return;
    _trackingRequested = true;
    if (_tracking != null || !_foreground) return;
    _trackingRetry?.cancel();
    _trackingRetry = null;
    final generation = ++_trackingGeneration;
    _tracking = service.watchPosition().listen(
      (value) {
        if (_disposed ||
            generation != _trackingGeneration ||
            !locationAllowed) {
          return;
        }
        final age = DateTime.now().difference(value.at);
        if (!value.accuracy.isFinite ||
            value.accuracy < 0 ||
            value.accuracy > 35 ||
            age > const Duration(seconds: 15) ||
            age < const Duration(seconds: -5) ||
            (fix != null && !value.at.isAfter(fix!.at)) ||
            !value.point.latitude.isFinite ||
            !value.point.longitude.isFinite ||
            value.point.latitude.abs() > 90 ||
            value.point.longitude.abs() > 180) {
          return;
        }
        fix = value;
        trackingError = null;
        _retrySeconds = 5;
        position = value.point;
        error = null;
        _notify();
      },
      onError: (Object e) {
        if (_disposed || generation != _trackingGeneration) return;
        if (e is LocationAccessException &&
            e.problem != LocationProblem.servicesDisabled) {
          error = e.message;
          stopTracking();
          _notify();
        } else {
          _recoverTracking(
            e is LocationAccessException
                ? e.message
                : 'GPS unavailable. Reconnecting…',
          );
        }
      },
      onDone: () {
        if (_disposed || generation != _trackingGeneration) return;
        _recoverTracking('GPS updates interrupted. Reconnecting…');
      },
    );
  }

  void _recoverTracking(String message) {
    _cancelTracking();
    trackingError = message;
    if (_trackingRequested && _foreground && locationAllowed && !_disposed) {
      final delay = _retrySeconds;
      _retrySeconds = (_retrySeconds * 2).clamp(5, 30);
      _trackingRetry?.cancel();
      _trackingRetry = Timer(Duration(seconds: delay), () {
        _trackingRetry = null;
        if (_trackingRequested &&
            _foreground &&
            locationAllowed &&
            !_disposed) {
          startTracking();
        }
      });
    }
    _notify();
  }

  void _cancelTracking() {
    _trackingGeneration++;
    unawaited(_tracking?.cancel());
    _tracking = null;
    fix = null;
  }

  void stopTracking() {
    _trackingRequested = false;
    _trackingRetry?.cancel();
    _trackingRetry = null;
    _retrySeconds = 5;
    trackingError = null;
    _cancelTracking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _trackingRetry?.cancel();
      _trackingRetry = null;
      _cancelTracking();
    } else if (_trackingRequested) {
      startTracking();
    }
  }

  LocationChoice get choice => settings.locationChoice;
  String get choiceLabel => switch (choice) {
    LocationChoice.ask => 'Choose location access',
    LocationChoice.everyOpen => 'Every app opening',
    LocationChoice.session =>
      _sessionActive ? 'This session only' : 'Session ended',
    LocationChoice.never => 'Off',
  };
  String get status =>
      '$choiceLabel · ${busy
          ? 'locating…'
          : trackingError != null
          ? 'reconnecting GPS'
          : position != null
          ? 'location ready'
          : error != null
          ? 'access unavailable'
          : 'manual planning'}';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> choose(LocationChoice value) async {
    _generation++;
    stopTracking();
    _sessionActive = value == LocationChoice.session;
    position = null;
    error = null;
    busy = false;
    final saving = settings.update(location: value);
    _notify();
    if (value == LocationChoice.everyOpen || value == LocationChoice.session) {
      await refresh(requestPermission: true);
    }
    await saving;
  }

  Future<void> refresh({bool requestPermission = false}) async {
    if (_trackingRequested ||
        busy ||
        (choice != LocationChoice.everyOpen &&
            !(choice == LocationChoice.session && _sessionActive))) {
      return;
    }
    final generation = ++_generation;
    busy = true;
    error = null;
    position = null;
    _notify();
    try {
      final result = await service.getCurrentPosition(
        requestPermission: requestPermission,
      );
      if (!_disposed && generation == _generation) position = result;
    } on LocationAccessException catch (e) {
      if (generation == _generation) error = e.message;
    } catch (_) {
      if (generation == _generation) {
        error = 'Location unavailable. Manual planning is available.';
      }
    } finally {
      if (generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopTracking();
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    super.dispose();
  }
}

class LocationScope extends InheritedNotifier<AppLocation> {
  const LocationScope({
    super.key,
    required AppLocation location,
    required super.child,
  }) : super(notifier: location);
  static AppLocation? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LocationScope>()?.notifier;
}

Future<void> showLocationChoice(
  BuildContext context,
  AppLocation location,
) async {
  if (location._choiceDialogOpen) return;
  location._choiceDialogOpen = true;
  try {
    final choice = await showDialog<LocationChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Use your location?'),
        content: const Text(
          'Use your position for trip starts, cooling distances and local weather. Weather checks send your position to Open-Meteo and NWS while the app is open. Pedestrian map queries share the trip area when you calculate or navigation needs a new area. Navigation follows GPS during an active walk while the app is in the foreground. Your choice is saved. Your device may also ask once for permission. Session-only access ends when you close the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, LocationChoice.everyOpen),
            child: const Text('Every time I open the app'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, LocationChoice.session),
            child: const Text('Just this session'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, LocationChoice.never),
            child: const Text('Never'),
          ),
        ],
      ),
    );
    if (choice != null) await location.choose(choice);
  } finally {
    location._choiceDialogOpen = false;
  }
}
