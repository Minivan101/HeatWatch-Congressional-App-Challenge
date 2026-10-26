class HeatGuardContract {
  const HeatGuardContract._();

  static Map<String, dynamic> examples(Object? value) {
    final data = _map(value);
    if (data['sampleOnly'] != true) {
      throw const FormatException('Heat Guard examples must be fictional');
    }
    final asOf = _instant(data['exampleAsOf']);
    final scenarios = _map(data['scenarios']);
    for (final name in ['active', 'checkedNone', 'unchecked', 'stale']) {
      scenario(scenarios[name], asOf);
    }
    return data;
  }

  static Map<String, dynamic> localExample(Object? value) {
    final data = _map(value);
    if (data['sampleOnly'] != true) {
      throw const FormatException('Local Heat Guard example must be fictional');
    }
    scenario(data['scenario'], _instant(data['exampleAsOf']));
    return data;
  }

  static Map<String, dynamic> scenario(Object? value, DateTime asOf) {
    final data = _map(value);
    final current = _map(data['current']);
    for (final field in [
      'temperatureC',
      'feelsLikeC',
      'humidityPercent',
      'uvIndex',
    ]) {
      if (current[field] is! num || !(current[field] as num).isFinite) {
        throw FormatException('Invalid Heat Guard $field');
      }
    }
    final humidity = current['humidityPercent'] as num;
    final uv = current['uvIndex'] as num;
    if (humidity < 0 || humidity > 100 || uv < 0) {
      throw const FormatException('Invalid Heat Guard reading');
    }
    final fetchedAt = _instant(data['fetchedAt']);
    if (fetchedAt.isAfter(asOf)) {
      throw const FormatException('Heat Guard example is from the future');
    }
    if (data['alertsChecked'] is! bool ||
        data['alerts'] is! List ||
        data['guidance'] is! List) {
      throw const FormatException('Heat Guard alert status is incomplete');
    }
    final alerts = data['alerts'] as List;
    if (data['alertsChecked'] == false && alerts.isNotEmpty) {
      throw const FormatException('Unchecked Heat Guard has alerts');
    }
    for (final raw in alerts) {
      final alert = _map(raw);
      for (final field in ['title', 'source']) {
        if (alert[field] is! String ||
            (alert[field] as String).trim().isEmpty) {
          throw FormatException('Heat Guard alert $field is missing');
        }
      }
      if (![
            'unknown',
            'minor',
            'moderate',
            'severe',
            'extreme',
          ].contains(alert['severity']) ||
          alert['sourceUrl'] is! String ||
          !(alert['sourceUrl'] as String).startsWith('https://')) {
        throw const FormatException('Heat Guard alert source is invalid');
      }
      _instant(alert['expiresAt']);
    }
    for (final guidance in data['guidance'] as List) {
      if (guidance is! String || guidance.trim().isEmpty) {
        throw const FormatException('Heat Guard guidance is invalid');
      }
    }
    return data;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('Heat Guard data is missing');
    }
    try {
      return Map<String, dynamic>.from(value);
    } catch (_) {
      throw const FormatException('Heat Guard fields are invalid');
    }
  }

  static DateTime _instant(Object? value) {
    if (value is! String ||
        !RegExp(r'(Z|[+-]\d\d:\d\d)$', caseSensitive: false).hasMatch(value)) {
      throw const FormatException('Heat Guard time needs a UTC offset');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw const FormatException('Invalid Heat Guard time');
    return parsed;
  }
}
