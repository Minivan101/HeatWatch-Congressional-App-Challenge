class CoolSpotsContract {
  const CoolSpotsContract._();

  static Map<String, dynamic> dataset(Object? value) {
    final data = _map(value, 'Cooling-center dataset');
    final id = _text(data['datasetId'], 'dataset ID');
    _text(data['region'], 'region');
    final agency = _text(data['sourceAgency'], 'source agency');
    final source = _https(data['sourceUrl'], 'county source');
    _instant(data['sourceCheckedAt'], 'source checked time');
    _text(data['timeZoneId'], 'time zone');
    final reference = _map(data['sampleReference'], 'example reference');
    _text(reference['label'], 'example reference label');
    location(reference['location']);
    final records = data['centers'];
    if (records is! List) {
      throw const FormatException('Cooling-center records are missing');
    }
    final ids = <String>{};
    for (final raw in records) {
      final center = _map(raw, 'Cooling-center record');
      final centerId = _text(center['id'], 'center ID');
      if (!ids.add(centerId) ||
          center['category'] != 'OFFICIAL_COOLING_CENTER' ||
          center['sourceAgency'] != agency ||
          center['sourceUrl'] != source) {
        throw const FormatException('Cooling-center source or ID mismatch');
      }
      _text(center['name'], 'center name');
      _text(center['address'], 'center address');
      _text(center['hours'], 'listed hours');
      location(center['location']);
      _instant(center['lastVerifiedAt'], 'record checked time');
      if (center['locationSourceUrl'] != null) {
        _https(center['locationSourceUrl'], 'coordinate source');
      }
      classifyDates(
        center['validFrom'],
        center['validUntil'],
        center['validFrom'],
      );
    }
    if (id == 'clark-county-june-2026-archived' &&
        records.any(
          (record) => (record as Map)['validUntil'].compareTo('2026-06-05') > 0,
        )) {
      throw const FormatException('Archived source has unexpected dates');
    }
    return data;
  }

  static Map<String, dynamic> fictionalPlaces(Object? value) {
    final data = _map(value, 'Indoor-place example');
    if (data['sampleOnly'] != true || data['indoorPlaces'] is! List) {
      throw const FormatException('Indoor-place example lacks sample label');
    }
    for (final raw in data['indoorPlaces'] as List) {
      final place = _map(raw, 'Indoor place');
      if (place['source'] != 'FICTIONAL_FIXTURE' ||
          place['category'] != 'INDOOR_PLACE' ||
          place['openNow'] != null) {
        throw const FormatException('Indoor place has unsafe source or status');
      }
      _text(place['placeId'], 'place ID');
      _text(place['name'], 'place name');
      _text(place['address'], 'place address');
      location(place['location']);
    }
    return data;
  }

  static Map<String, dynamic> localCenters(Object? value) {
    final response = _map(value, 'Local center response');
    if (response['source'] != 'LOCAL_FIRESTORE_EMULATOR') {
      throw const FormatException('Center response is not from the emulator');
    }
    final saved = dataset(response['dataset']);
    final localDate = _day(response['localDate'], 'local date');
    final statuses = _map(response['dateStatuses'], 'center date statuses');
    final records = saved['centers'] as List;
    if (statuses.length != records.length) {
      throw const FormatException('Center date statuses are incomplete');
    }
    for (final raw in records) {
      final center = raw as Map<String, dynamic>;
      final expected = classifyDates(
        center['validFrom'],
        center['validUntil'],
        localDate,
      );
      if (statuses[center['id']] != expected) {
        throw const FormatException('Center date status does not match source');
      }
    }
    return response;
  }

  static String classifyDates(Object? start, Object? end, Object? day) {
    final from = _day(start, 'activation start');
    final until = _day(end, 'activation end');
    final current = _day(day, 'local date');
    if (from.compareTo(until) > 0) {
      throw const FormatException('Cooling-center dates are reversed');
    }
    if (current.compareTo(from) < 0) return 'upcoming';
    if (current.compareTo(until) > 0) return 'expired';
    return 'date-listed';
  }

  static Map<String, dynamic> location(Object? value) {
    final point = _map(value, 'Location');
    final lat = point['latitude'];
    final lng = point['longitude'];
    if (lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      throw const FormatException('Invalid place coordinate');
    }
    return point;
  }

  static Map<String, dynamic> _map(Object? value, String label) {
    if (value is! Map) throw FormatException('$label is missing');
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      throw FormatException('$label has invalid fields');
    }
  }

  static String _text(Object? value, String label) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$label is missing');
    }
    return value;
  }

  static String _https(Object? value, String label) {
    final text = _text(value, label);
    if (!text.startsWith('https://')) {
      throw FormatException('$label is not an HTTPS source');
    }
    return text;
  }

  static DateTime _instant(Object? value, String label) {
    final text = _text(value, label);
    final parsed = DateTime.tryParse(text);
    if (parsed == null || !text.contains(RegExp(r'(Z|[+-]\d\d:\d\d)$'))) {
      throw FormatException('$label is not a dated instant');
    }
    return parsed;
  }

  static String _day(Object? value, String label) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw FormatException('$label is not YYYY-MM-DD');
    }
    final parsed = DateTime.tryParse('${value}T00:00:00Z');
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw FormatException('$label is not a real calendar day');
    }
    return value;
  }
}
