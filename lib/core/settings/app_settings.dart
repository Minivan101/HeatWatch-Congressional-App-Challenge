import 'dart:convert';

import 'package:flutter/material.dart';

import 'settings_store.dart';
import 'route_preference.dart';
export 'route_preference.dart';

enum LocationChoice { ask, everyOpen, session, never }

class AppSettings extends ChangeNotifier {
  AppSettings({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) {
    final store = SettingsStore();
    _read = read ?? store.read;
    _write = write ?? store.write;
  }
  late final Future<String?> Function() _read;
  late final Future<void> Function(String) _write;
  bool loaded = false;
  LocationChoice locationChoice = LocationChoice.ask;
  ThemeMode themeMode = ThemeMode.system;
  bool fahrenheit = true;
  bool imperial = true;
  RoutePreference routePreference = RoutePreference.balanced;
  bool routePreferencePromptSeen = false;
  String? saveError;
  Future<void> _pending = Future.value();
  int _version = 0;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final version = _version;
    try {
      final text = await _read();
      if (_disposed || text == null || version != _version) return;
      final data = jsonDecode(text) as Map;
      themeMode = ThemeMode.values.firstWhere(
        (v) => v.name == data['theme'],
        orElse: () => ThemeMode.system,
      );
      fahrenheit = data['fahrenheit'] is bool
          ? data['fahrenheit'] == true
          : true;
      imperial = data['imperial'] is bool
          ? data['imperial'] == true
          : fahrenheit;
      fahrenheit = imperial;
      locationChoice = LocationChoice.values.firstWhere(
        (v) => v.name == data['location'],
        orElse: () => LocationChoice.ask,
      );
      routePreference = RoutePreference.values.firstWhere(
        (v) => v.name == data['routePreference'],
        orElse: () => RoutePreference.balanced,
      );
      routePreferencePromptSeen = data['routePreferencePromptSeen'] == true;
      _notify();
    } catch (_) {
      // keep current settings
    } finally {
      loaded = true;
      _notify();
    }
  }

  Future<void> update({
    ThemeMode? theme,
    bool? useFahrenheit,
    bool? useImperial,
    LocationChoice? location,
    RoutePreference? preference,
    bool? preferencePromptSeen,
  }) {
    final version = ++_version;
    themeMode = theme ?? themeMode;
    imperial = useImperial ?? useFahrenheit ?? imperial;
    fahrenheit = imperial;
    locationChoice = location ?? locationChoice;
    routePreference = preference ?? routePreference;
    routePreferencePromptSeen =
        preferencePromptSeen ?? routePreferencePromptSeen;
    saveError = null;
    final value = jsonEncode({
      'theme': themeMode.name,
      'fahrenheit': fahrenheit,
      'imperial': imperial,
      'location': locationChoice.name,
      'routePreference': routePreference.name,
      'routePreferencePromptSeen': routePreferencePromptSeen,
    });
    _notify();
    return _pending = _pending.then((_) async {
      try {
        await _write(value);
        if (version == _version) saveError = null;
      } catch (_) {
        if (version == _version) {
          saveError =
              'Settings changed for this session, but could not be saved.';
        }
      }
      if (version == _version) _notify();
    });
  }

  String temperature(double? c, {String missing = 'unavailable'}) => c == null
      ? missing
      : '${(fahrenheit ? c * 9 / 5 + 32 : c).toStringAsFixed(1)}°${fahrenheit ? 'F' : 'C'}';

  String distance(double meters, {bool short = false}) {
    if (imperial) {
      return short && meters < 160.9344
          ? '${(meters * 3.28084).round()} ft'
          : '${(meters / 1609.344).toStringAsFixed(1)} mi';
    }
    return short && meters < 1000
        ? '${meters.round()} m'
        : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String radius(int miles) =>
      imperial ? '$miles miles' : '${(miles * 1.609344).toStringAsFixed(1)} km';

  String windSpeed(double kilometersPerHour) => imperial
      ? '${(kilometersPerHour / 1.609344).round()} mph'
      : '${kilometersPerHour.round()} km/h';

  String walkingInstruction(String instruction) {
    if (!imperial) return instruction;
    return instruction.replaceFirstMapped(
      RegExp(r'^In (\d+) m, '),
      (match) =>
          'In ${((int.parse(match[1]!) * 3.28084) / 5).round() * 5} ft, ',
    );
  }
}

class SettingsScope extends InheritedNotifier<AppSettings> {
  const SettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);
  static AppSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier;
  static String temperature(
    BuildContext context,
    double? c, {
    String missing = 'unavailable',
  }) =>
      maybeOf(context)?.temperature(c, missing: missing) ??
      (c == null ? missing : '${c.toStringAsFixed(1)}°C');

  static String distance(
    BuildContext context,
    double meters, {
    bool short = false,
  }) =>
      maybeOf(context)?.distance(meters, short: short) ??
      (short && meters < 160.9344
          ? '${(meters * 3.28084).round()} ft'
          : '${(meters / 1609.344).toStringAsFixed(1)} mi');
}
