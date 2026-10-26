import '../../../core/models/coordinates.dart';

class CityPlace {
  const CityPlace(
    this.name,
    this.address,
    this.point, {
    this.aliases = const [],
    this.sourceUrl,
    this.precision,
  });
  final String name, address;
  final Coordinates point;
  final List<String> aliases;
  final String? sourceUrl, precision;
}
