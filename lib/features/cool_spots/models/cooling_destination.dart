import '../../../core/models/coordinates.dart';

class CoolingDestination {
  const CoolingDestination({
    required this.id,
    required this.name,
    required this.address,
    required this.location,
    required this.sourceUrl,
    required this.precision,
    this.startFromCurrentLocation = false,
  });
  final String id;
  final String name;
  final String address;
  final Coordinates location;
  final String sourceUrl;
  final String precision;
  final bool startFromCurrentLocation;

  factory CoolingDestination.fromStation(
    Map<String, dynamic> station, {
    bool startFromCurrentLocation = false,
  }) {
    final point = station['coordinates'] as Map;
    return CoolingDestination(
      startFromCurrentLocation: startFromCurrentLocation,
      id: station['id'] as String,
      name: station['name'] as String,
      address: station['address'] as String,
      location: Coordinates(
        latitude: (point['latitude'] as num).toDouble(),
        longitude: (point['longitude'] as num).toDouble(),
      ),
      sourceUrl: point['sourceUrl'] as String,
      precision: point['precision'] as String,
    );
  }
}
