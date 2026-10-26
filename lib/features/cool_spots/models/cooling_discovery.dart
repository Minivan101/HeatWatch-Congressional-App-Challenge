import '../../../core/models/coordinates.dart';
import '../services/cooling_actions.dart';

const coolingCategories = [
  'All',
  'Libraries',
  'Community',
  'Indoor Places',
  'Parks',
];
const coolingRadiusChoices = [5, 10, 15];
const metersPerMile = 1609.344;

String? coolingCategory(Map<String, dynamic> place) {
  final name = (place['name'] as String).toLowerCase();
  if (name.contains('library')) return 'Libraries';
  if (place['kind'] == 'park') return 'Parks';
  if (name.contains('community center') ||
      name.contains('recreation') ||
      name.contains('senior center') ||
      name.contains('multi-generational')) {
    return 'Community';
  }
  if (['mall', 'indoorDestination'].contains(place['kind'])) {
    return 'Indoor Places';
  }
  return null;
}

List<Map<String, dynamic>> nearbyCoolingPlaces(
  Iterable<Map<String, dynamic>> places,
  Coordinates origin, {
  String category = 'All',
  String query = '',
  int radiusMiles = 5,
}) {
  if (!coolingRadiusChoices.contains(radiusMiles)) {
    throw ArgumentError.value(
      radiusMiles,
      'radiusMiles',
      'Choose 5, 10 or 15 miles',
    );
  }
  final terms = query
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty);
  final result = places.where((place) {
    final type = coolingCategory(place);
    final point = place['coordinates'];
    return type != null &&
        point is Map &&
        (category == 'All' || category == type) &&
        terms.every(
          (term) => '${place['name']} ${place['address']}'
              .toLowerCase()
              .contains(term),
        ) &&
        CoolingActions.distanceMeters(origin, point) <=
            radiusMiles * metersPerMile;
  }).toList();
  result.sort((a, b) {
    final distance = CoolingActions.distanceMeters(
      origin,
      a['coordinates'] as Map,
    ).compareTo(CoolingActions.distanceMeters(origin, b['coordinates'] as Map));
    return distance != 0
        ? distance
        : (a['name'] as String).compareTo(b['name'] as String);
  });
  return result;
}
