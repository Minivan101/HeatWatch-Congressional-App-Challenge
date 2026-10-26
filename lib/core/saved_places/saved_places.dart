import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/coordinates.dart';
import '../../features/shade_route/models/city_place.dart';
import '../../features/cool_spots/models/cooling_destination.dart';
import 'saved_places_store.dart';

enum PlaceLabel { home, work }

class SavedPlace {
  const SavedPlace({
    required this.name,
    required this.address,
    required this.point,
    required this.sourceUrl,
    required this.precision,
    this.nickname = '',
  });
  final String name, address, sourceUrl, precision, nickname;
  final Coordinates point;
  String get id =>
      '${name.trim().toLowerCase()}|${point.latitude.toStringAsFixed(5)}|${point.longitude.toStringAsFixed(5)}';
  String get title => nickname.isEmpty ? name : nickname;
  CityPlace get cityPlace => CityPlace(
    title,
    address,
    point,
    sourceUrl: sourceUrl,
    precision: precision,
  );
  CoolingDestination get destination => CoolingDestination(
    id: 'saved:$id',
    name: title,
    address: address,
    location: point,
    sourceUrl: sourceUrl,
    precision: precision,
  );
  factory SavedPlace.fromCity(CityPlace place) => SavedPlace(
    name: place.name,
    address: place.address,
    point: place.point,
    sourceUrl: place.sourceUrl ?? 'https://www.openstreetmap.org',
    precision: place.precision ?? 'Selected map point',
  );
  factory SavedPlace.fromDestination(CoolingDestination place) => SavedPlace(
    name: place.name,
    address: place.address,
    point: place.location,
    sourceUrl: place.sourceUrl,
    precision: place.precision,
  );
  Map<String, Object> toJson() => {
    'name': name,
    'address': address,
    'latitude': point.latitude,
    'longitude': point.longitude,
    'sourceUrl': sourceUrl,
    'precision': precision,
    'nickname': nickname,
  };
  static SavedPlace? parse(Object? data) {
    if (data is! Map ||
        data['name'] is! String ||
        (data['name'] as String).trim().isEmpty ||
        data['latitude'] is! num ||
        data['longitude'] is! num) {
      return null;
    }
    final point = Coordinates(
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
    );
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180) {
      return null;
    }
    return SavedPlace(
      name: data['name'] as String,
      address: data['address'] is String ? data['address'] as String : '',
      point: point,
      sourceUrl: data['sourceUrl'] is String ? data['sourceUrl'] as String : '',
      precision: data['precision'] is String
          ? data['precision'] as String
          : 'Saved map point',
      nickname: data['nickname'] is String ? data['nickname'] as String : '',
    );
  }
}

// home, work and favorites
class SavedPlaces extends ChangeNotifier {
  SavedPlaces({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) {
    final store = SavedPlacesStore();
    _read = read ?? store.read;
    _write = write ?? store.write;
  }
  late final Future<String?> Function() _read;
  late final Future<void> Function(String) _write;
  final _places = <String, SavedPlace>{};
  final _favorites = <String>{};
  String? _homeId, _workId;
  String? error;
  bool loaded = false, restoreFailed = false, _disposed = false;
  int _version = 0;
  Future<void> _pending = Future.value();
  List<SavedPlace> get favorites =>
      List.unmodifiable(_favorites.map((id) => _places[id]!).toList());
  SavedPlace? labeled(PlaceLabel label) =>
      _places[label == PlaceLabel.home ? _homeId : _workId];
  SavedPlace canonical(SavedPlace place) {
    for (final existing in _places.values) {
      if (existing.id == place.id ||
          ((existing.point.latitude - place.point.latitude).abs() < .000001 &&
              (existing.point.longitude - place.point.longitude).abs() <
                  .000001 &&
              existing.sourceUrl == place.sourceUrl &&
              (existing.name == place.name || existing.title == place.name))) {
        return existing;
      }
    }
    return place;
  }

  bool isFavorite(SavedPlace place) => _favorites.contains(canonical(place).id);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    final version = _version;
    try {
      restoreFailed = false;
      error = null;
      final text = await _read();
      if (_disposed || version != _version || text == null) return;
      final data = jsonDecode(text);
      if (data is! Map || data['version'] != 1 || data['places'] is! List) {
        throw const FormatException('Invalid saved places');
      }
      for (final row in data['places'] as List) {
        final place = SavedPlace.parse(row);
        if (place != null) _places[place.id] = place;
      }
      _favorites.addAll(
        (data['favoriteIds'] is List ? data['favoriteIds'] as List : const [])
            .whereType<String>()
            .where(_places.containsKey),
      );
      _homeId = _places.containsKey(data['homeId'])
          ? data['homeId'] as String
          : null;
      _workId = _places.containsKey(data['workId'])
          ? data['workId'] as String
          : null;
    } catch (_) {
      restoreFailed = true;
      error =
          'Saved places could not be restored. Retry before making changes.';
    } finally {
      loaded = true;
      _notify();
    }
  }

  Future<void> toggleFavorite(SavedPlace place) {
    if (!loaded || restoreFailed) return Future.value();
    place = canonical(place);
    if (!_favorites.remove(place.id)) {
      _places.putIfAbsent(place.id, () => place);
      _favorites.add(place.id);
    }
    return _save();
  }

  Future<void> setLabel(PlaceLabel label, SavedPlace? place) {
    if (!loaded || restoreFailed) return Future.value();
    if (place != null) {
      place = canonical(place);
      _places.putIfAbsent(place.id, () => place!);
    }
    if (label == PlaceLabel.home) {
      _homeId = place?.id;
    } else {
      _workId = place?.id;
    }
    return _save();
  }

  Future<void> rename(SavedPlace place, String name) {
    if (!_places.containsKey(place.id)) return Future.value();
    _places[place.id] = SavedPlace(
      name: place.name,
      address: place.address,
      point: place.point,
      sourceUrl: place.sourceUrl,
      precision: place.precision,
      nickname: name.trim().substring(0, name.trim().length.clamp(0, 80)),
    );
    return _save();
  }

  Future<void> retrySave() => _save();
  Future<void> _save() {
    final version = ++_version;
    _places.removeWhere(
      (id, _) => !_favorites.contains(id) && id != _homeId && id != _workId,
    );
    error = null;
    final text = jsonEncode({
      'version': 1,
      'places': _places.values.map((p) => p.toJson()).toList(),
      'favoriteIds': _favorites.toList(),
      'homeId': _homeId,
      'workId': _workId,
    });
    _notify();
    return _pending = _pending.then((_) async {
      try {
        await _write(text);
      } catch (_) {
        if (version == _version) error = 'Places changed for this session, but could not be saved on this device.';
      }
      if (version == _version) _notify();
    });
  }
}

class SavedPlacesScope extends InheritedNotifier<SavedPlaces> {
  const SavedPlacesScope({
    super.key,
    required SavedPlaces places,
    required super.child,
  }) : super(notifier: places);
  static SavedPlaces? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SavedPlacesScope>()?.notifier;
}
