import 'dart:math' as math;

import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/coordinates.dart';

class CoolingActions {
  const CoolingActions();
  Future<bool> openSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> dial(String number) => launchUrl(
    Uri(scheme: 'tel', path: number.replaceAll(RegExp(r'[^0-9+]'), '')),
    mode: LaunchMode.externalApplication,
  );

  static Uri directionsUri(Map<String, dynamic> place, {Coordinates? origin}) {
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '${place['name']}, ${place['address']}',
      if (origin != null) 'origin': '${origin.latitude},${origin.longitude}',
      'travelmode': 'walking',
    });
  }

  Future<bool> directions(
    Map<String, dynamic> place, {
    Coordinates? origin,
  }) async {
    try {
      return await launchUrl(
        directionsUri(place, origin: origin),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  static double distanceMeters(Coordinates origin, Map point) {
    const radius = 6371000.0;
    final a = origin.latitude * math.pi / 180;
    final b = (point['latitude'] as num) * math.pi / 180;
    final delta =
        ((point['longitude'] as num) - origin.longitude) * math.pi / 180;
    final h =
        math.pow(math.sin((b - a) / 2), 2) +
        math.cos(a) * math.cos(b) * math.pow(math.sin(delta / 2), 2);
    final safe = h.clamp(0.0, 1.0);
    return 2 * radius * math.atan2(math.sqrt(safe), math.sqrt(1 - safe));
  }
}
