import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/models/coordinates.dart';
import '../models/city_place.dart';

class PlaceDirectory {
  static Future<List<CityPlace>>? _loaded;
  static Future<List<CityPlace>> load() => _loaded ??= _load();
  static Future<List<CityPlace>> _load() async {
    try {
      return parse(
        jsonDecode(await rootBundle.loadString('data/places/las_vegas.json')),
      );
    } catch (_) {
      _loaded = null;
      rethrow;
    }
  }

  static List<CityPlace> parse(Object? input) {
    if (input is! Map || input['version'] != 1 || input['places'] is! List) {
      throw const FormatException('Invalid destination directory');
    }
    final places = <CityPlace>[];
    for (final row in input['places'] as List) {
      if (row is! Map ||
          row['name'] is! String ||
          (row['name'] as String).trim().isEmpty ||
          row['latitude'] is! num ||
          row['longitude'] is! num) {
        continue;
      }
      final lat = (row['latitude'] as num).toDouble(),
          lon = (row['longitude'] as num).toDouble();
      if (!lat.isFinite ||
          !lon.isFinite ||
          lat < 36.04 ||
          lat > 36.4015 ||
          lon < -115.50 ||
          lon > -115.04) {
        continue;
      }
      places.add(
        CityPlace(
          row['name'] as String,
          row['address'] as String? ?? '',
          Coordinates(latitude: lat, longitude: lon),
          aliases: (row['aliases'] as List? ?? []).whereType<String>().toList(
            growable: false,
          ),
          sourceUrl: row['sourceUrl'] as String?,
          precision: row['precision'] as String?,
        ),
      );
    }
    return List.unmodifiable(places);
  }
}

String normalizePlaceText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

int placeMatchRank(CityPlace p, String query) {
  final term = normalizePlaceText(query), name = normalizePlaceText(p.name);
  if (name == term) return 0;
  if (name.startsWith(term)) return 1;
  if (name.contains(term)) return 2;
  final aliases = normalizePlaceText(p.aliases.join(' '));
  if (aliases.contains(term)) return 3;
  final address = normalizePlaceText(p.address);
  if (address.contains(term)) return 4;
  final full = '$name $aliases $address';
  return term.split(' ').every(full.contains) ? 5 : 100;
}
