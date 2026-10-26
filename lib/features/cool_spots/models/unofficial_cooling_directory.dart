class UnofficialCoolingDirectory {
  UnofficialCoolingDirectory._(this.data);
  final Map<String, dynamic> data;
  List<Map<String, dynamic>> get places =>
      (data['places'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get sources =>
      (data['sources'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> source(String id) =>
      sources.singleWhere((s) => s['id'] == id);

  static String methodLabel(Map<String, dynamic> place) {
    final methods = place['methods'] as List;
    return [
      if (methods.contains('airConditioning')) 'Air conditioning · indoors',
      if (methods.contains('indoorVenues')) 'Indoor venues · outdoor walkways',
      if (methods.contains('drinkingWater'))
        place['kind'] == 'park'
            ? 'Drinking water · outdoors'
            : 'Drinking water',
    ].join(' / ');
  }

  static UnofficialCoolingDirectory parse(Object? value) {
    void require(bool condition) {
      if (!condition) {
        throw const FormatException('Invalid community cooling directory');
      }
    }

    bool text(Object? v) => v is String && v.trim().isNotEmpty;
    bool https(Object? v) {
      final uri = v is String ? Uri.tryParse(v) : null;
      return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty;
    }

    require(value is Map<String, dynamic>);
    final data = value as Map<String, dynamic>;
    require(data['schemaVersion'] == 1);
    require(
      data['checkedOn'] is String &&
          RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(data['checkedOn']) &&
          DateTime.tryParse(data['checkedOn'])
                  ?.toIso8601String()
                  .substring(0, 10) ==
              data['checkedOn'],
    );
    require(data['sources'] is List && data['places'] is List);
    final sources = data['sources'] as List;
    final places = data['places'] as List;
    require(
      places.isNotEmpty &&
          places.length <= 100 &&
          data['placeCount'] == places.length,
    );
    final ids = <String>{};
    for (final raw in sources) {
      require(raw is Map<String, dynamic>);
      final s = raw as Map<String, dynamic>;
      require(text(s['id']) && text(s['title']) && https(s['url']));
      require(ids.add(s['id'] as String));
    }
    final placeIds = <String>{};
    for (final raw in places) {
      require(raw is Map<String, dynamic>);
      final p = raw as Map<String, dynamic>;
      require(text(p['id']) && placeIds.add(p['id'] as String));
      require(text(p['name']) && text(p['address']) && text(p['access']));
      require(
        p['area'] == 'Las Vegas area' && p['officialCoolingStation'] == false,
      );
      require(
        [
          'park',
          'mall',
          'restaurant',
          'communityVenue',
          'indoorDestination',
        ].contains(p['kind']),
      );
      require(p['methods'] is List && (p['methods'] as List).isNotEmpty);
      require(
        (p['methods'] as List).every(
          (m) =>
              ['drinkingWater', 'airConditioning', 'indoorVenues'].contains(m),
        ),
      );
      require(
        p['aliases'] is List &&
            (p['aliases'] as List).every((a) => a is String),
      );
      require(p['hours'] == null || text(p['hours']));
      require(p['phone'] == null || text(p['phone']));
      require(
        p['sourceIds'] is List &&
            (p['sourceIds'] as List).isNotEmpty &&
            (p['sourceIds'] as List).every(ids.contains),
      );
      require(p['evidence'] is Map && (p['evidence'] as Map).isNotEmpty);
      if (p['kind'] == 'indoorDestination') {
        final evidence = p['evidence'] as Map;
        require(
          text(evidence['coolingScope']) && https(evidence['scopeSource']),
        );
        require(
          evidence['reviewedOn'] is String &&
              DateTime.tryParse(evidence['reviewedOn']) != null,
        );
      }
      if ((p['methods'] as List).contains('indoorVenues')) {
        require(
          p['kind'] == 'indoorDestination' &&
              !(p['methods'] as List).contains('airConditioning') &&
              text((p['evidence'] as Map)['indoorVenues']) &&
              text(p['scopeLabel']),
        );
      }
      require(p['coordinates'] is Map);
      final point = p['coordinates'] as Map;
      require(point['latitude'] is num && point['longitude'] is num);
      final lat = (point['latitude'] as num).toDouble();
      final lon = (point['longitude'] as num).toDouble();
      require(
        lat.isFinite &&
            lon.isFinite &&
            lat >= 35.8 &&
            lat <= 36.5 &&
            lon >= -115.5 &&
            lon <= -114.9,
      );
      require(text(point['precision']) && https(point['sourceUrl']));
    }
    return UnofficialCoolingDirectory._(data);
  }
}
