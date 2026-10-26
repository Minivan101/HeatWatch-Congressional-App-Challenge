import '../models/free_weather.dart';

List<NwsAlert> activeAlerts(AlertReading reading, DateTime now) {
  final unique = <String, NwsAlert>{};
  for (final alert in reading.alerts) {
    final old = unique[alert.id];
    if (old == null || !alert.sent.isBefore(old.sent)) unique[alert.id] = alert;
  }
  final messages = unique.values.toList()
    ..sort((a, b) => b.sent.compareTo(a.sent));
  final suppressed = <String>{};
  for (final message in messages) {
    if (message.status != 'Actual' ||
        !['Update', 'Cancel'].contains(message.messageType) ||
        message.effective.isAfter(now) ||
        message.sent.isAfter(now)) {
      continue;
    }
    final refs = (message.raw['properties'] as Map?)?['references'];
    if (refs is List) {
      for (final ref in refs) {
        if (ref is Map && ref['identifier'] is String) {
          suppressed.add(ref['identifier'] as String);
        }
      }
    }
  }
  final result = messages
      .where(
        (a) =>
            a.status == 'Actual' &&
            ['Alert', 'Update'].contains(a.messageType) &&
            !suppressed.contains(a.id) &&
            !a.sent.isAfter(now) &&
            !a.effective.isAfter(now) &&
            a.expires.isAfter(now) &&
            (a.ends == null || a.ends!.isAfter(now)),
      )
      .toList();
  const rank = {
    'Extreme': 4,
    'Severe': 3,
    'Moderate': 2,
    'Minor': 1,
    'Unknown': 0,
  };
  result.sort((a, b) {
    final severity = (rank[b.severity] ?? 0).compareTo(rank[a.severity] ?? 0);
    return severity != 0 ? severity : b.sent.compareTo(a.sent);
  });
  return List.unmodifiable(result);
}
