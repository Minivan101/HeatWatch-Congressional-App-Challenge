import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'walking_limits.dart';
import 'place_directory.dart';
import '../models/city_place.dart';
export '../models/city_place.dart';
import 'walking_request_policy.dart';
import '../../../core/models/coordinates.dart';
import 'local_shade_calculator.dart';

class WalkingStep {
  const WalkingStep(this.atMeters, this.instruction);
  final double atMeters;
  final String instruction;
}

class CityWalkingRoute {
  const CityWalkingRoute(
    this.geometry,
    this.distanceMeters, {
    this.steps = const [],
    this.inferredStreetMeters = 0,
  });
  final WalkingGeometry geometry;
  final double distanceMeters;

  final double inferredStreetMeters;
  final List<WalkingStep> steps;
}

class CityTripService {
  CityTripService({
    http.Client? client,
    DateTime Function()? now,
    Future<List<CityPlace>> Function()? loadPlaces,
  }) : _loadPlaces = loadPlaces ?? PlaceDirectory.load,
       client = client ?? http.Client(),
       _now = now ?? DateTime.now;
  final Future<List<CityPlace>> Function() _loadPlaces;
  final DateTime Function() _now;
  final _retryAt = <String, DateTime>{};
  final http.Client client;
  final _searchCache = <String, List<CityPlace>>{};
  final _routeCache =
      <String, ({List<CityWalkingRoute> routes, DateTime fetched})>{};
  Future<void> _queue = Future.value();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  Future<http.Response> _get(Uri uri) async {
    late http.Response response;
    final request = _queue.then((_) async {
      if (_retryAt[uri.host]?.isAfter(_now()) == true) {
        throw const FormatException(
          'Walking service is temporarily busy. Try again later.',
        );
      }
      final wait = 1100 - _now().difference(_last).inMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      _last = _now();
      response = await client
          .get(
            uri,
            headers: {
              'User-Agent':
                  'HeatWatch/0.1 (com.ivantrac.heatwatch student prototype)',
            },
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode == 429 || response.statusCode == 503) {
        _retryAt[uri.host] =
            walkingRetryTime(response.headers['retry-after'], _now()) ??
            _now().add(const Duration(seconds: 30));
      }
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 8 * 1024 * 1024) {
        throw const FormatException('Service unavailable. Try again later.');
      }
    });
    _queue = request.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await request;
    return response;
  }

  static const planningCenter = Coordinates(
    latitude: 36.1699,
    longitude: -115.1398,
  );

  static bool isInPlanningArea(Coordinates p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude >= 36.04 &&
      p.latitude <= 36.4015 &&
      p.longitude >= -115.50 &&
      p.longitude <= -115.04;

  static void validatePoint(Coordinates p) {
    if (!isInPlanningArea(p)) {
      throw const FormatException(
        'Choose a point in the Las Vegas planning area.',
      );
    }
  }

  Future<List<CityPlace>> search(String query) => _search(query);

  Future<List<CityPlace>> searchOnline(String query) =>
      _search(query, onlineOnly: true);

  Future<List<CityPlace>> _search(
    String query, {
    bool onlineOnly = false,
  }) async {
    final q = query.trim();
    if (q.length < 3 || q.length > 160) {
      throw const FormatException(
        'Enter a place or address (3–160 characters).',
      );
    }
    final coordinate = RegExp(
      r'^(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)$',
    ).firstMatch(q);
    if (coordinate != null) {
      final point = Coordinates(
        latitude: double.parse(coordinate[1]!),
        longitude: double.parse(coordinate[2]!),
      );
      validatePoint(point);
      return [
        CityPlace(
          'Map coordinates',
          q,
          point,
          precision: 'user selected coordinates',
        ),
      ];
    }
    final focus = planningCenter;
    final key =
        '${onlineOnly ? 'online' : 'local'}|${q.toLowerCase()}|${focus.latitude.toStringAsFixed(3)}|${focus.longitude.toStringAsFixed(3)}';
    if (_searchCache[key] case final cached?) return cached;
    List<CityPlace> local = [];
    try {
      if (!onlineOnly) {
        local = (await _loadPlaces())
            .where((p) => placeMatchRank(p, q) < 100)
            .toList();
      }
    } catch (_) {
      // try online search
    }
    List<CityPlace> finish(List<CityPlace> candidates) {
      double distance(CityPlace p) =>
          math.pow(p.point.latitude - focus.latitude, 2).toDouble() +
          math
              .pow(
                (p.point.longitude - focus.longitude) *
                    math.cos(focus.latitude * math.pi / 180),
                2,
              )
              .toDouble();
      candidates.sort((a, b) {
        final match = placeMatchRank(a, q).compareTo(placeMatchRank(b, q));
        return match != 0 ? match : distance(a).compareTo(distance(b));
      });
      final result = <CityPlace>[];
      for (final p in candidates) {
        if (result.any(
          (other) =>
              normalizePlaceText(other.name) == normalizePlaceText(p.name) &&
              _nearPlace(other.point, p.point),
        )) {
          continue;
        }
        result.add(p);
        if (result.length == 200) break;
      }
      if (_searchCache.length >= 24) {
        _searchCache.remove(_searchCache.keys.first);
      }
      return _searchCache[key] = List.unmodifiable(result);
    }

    if (local.isNotEmpty) return finish(local);
    final response = await _get(
      Uri.https('photon.komoot.io', '/api/', {
        'q': q,
        'lat': '${focus.latitude}',
        'lon': '${focus.longitude}',
        'limit': '20',
        'dedupe': '0',
        'lang': 'en',
        'bbox': '-115.50,36.04,-115.04,36.4015',
      }),
    );
    final data = jsonDecode(response.body) as Map;
    final places = <CityPlace>[];
    final seen = <String>{};
    for (final f in data['features'] as List) {
      try {
        if (f['geometry']['type'] != 'Point') continue;
        final c = f['geometry']['coordinates'] as List;
        final p = Coordinates(
          latitude: (c[1] as num).toDouble(),
          longitude: (c[0] as num).toDouble(),
        );
        validatePoint(p);
        final props = f['properties'] as Map;
        final address = [
          props['housenumber'],
          props['street'],
          props['city'],
          props['postcode'],
        ].where((v) => v is String && v.isNotEmpty).join(' ');
        final name =
            props['name'] as String? ?? (address.isEmpty ? q : address);
        final identity =
            '${name.toLowerCase()}|${p.latitude.toStringAsFixed(5)}|${p.longitude.toStringAsFixed(5)}';
        if (seen.add(identity)) places.add(CityPlace(name, address, p));
      } catch (_) {
        // skip this place
      }
    }
    return finish(places);
  }

  static bool _nearPlace(Coordinates a, Coordinates b) =>
      (a.latitude - b.latitude).abs() < .00015 &&
      (a.longitude - b.longitude).abs() < .00018;

  Future<CityWalkingRoute> walk(
    Coordinates start,
    Coordinates end, {
    List<Coordinates> via = const [],
  }) async => (await walkAlternatives(start, end, via: via)).first;

  Future<List<CityWalkingRoute>> walkAlternatives(
    Coordinates start,
    Coordinates end, {
    List<Coordinates> via = const [],
  }) async {
    final points = [start, ...via, end];
    if (points.length > 8) {
      throw const FormatException('Use at most six intermediate points.');
    }
    points.forEach(validatePoint);
    final path = points.map((p) => '${p.longitude},${p.latitude}').join(';');
    if (_routeCache[path] case final cached?) {
      if (_now().difference(cached.fetched) < const Duration(minutes: 30)) {
        return cached.routes;
      }
      _routeCache.remove(path);
    }
    final uri = Uri.https(
      'routing.openstreetmap.de',
      '/routed-foot/route/v1/foot/$path',
      {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'true',
        'annotations': 'duration',
        'alternatives': via.isEmpty ? '3' : 'false',
      },
    );
    final response = await _get(uri);
    final result = parseAlternatives(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (!_near(result.first.geometry.points.first, start) ||
        !_near(result.first.geometry.points.last, end)) {
      throw const FormatException(
        'Choose a point closer to a mapped walking path.',
      );
    }

    final matched = result
        .where(
          (r) =>
              _near(r.geometry.points.first, start) &&
              _near(r.geometry.points.last, end),
        )
        .toList(growable: false);
    if (_routeCache.length >= 16) _routeCache.remove(_routeCache.keys.first);
    final routes = List<CityWalkingRoute>.unmodifiable(matched);
    _routeCache[path] = (routes: routes, fetched: _now());
    return routes;
  }

  static List<CityWalkingRoute> parseAlternatives(Map<String, dynamic> data) {
    final primary = parseRoute(data);
    final routes = <CityWalkingRoute>[primary];
    String signature(CityWalkingRoute r) => r.geometry.points
        .map(
          (p) =>
              '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}',
        )
        .join(';');
    final seen = <String>{signature(primary)};
    for (final candidate in (data['routes'] as List).skip(1).take(5)) {
      try {
        final parsed = parseRoute({
          ...data,
          'routes': [candidate],
        });
        if (_near(
              parsed.geometry.points.first,
              primary.geometry.points.first,
            ) &&
            _near(parsed.geometry.points.last, primary.geometry.points.last) &&
            seen.add(signature(parsed))) {
          routes.add(parsed);
        }
      } catch (_) {
        // skip this route
      }
      if (routes.length == 6) break;
    }
    return List.unmodifiable(routes);
  }

  static bool _near(Coordinates a, Coordinates b) {
    final dy = (a.latitude - b.latitude) * 111320;
    final dx =
        (a.longitude - b.longitude) *
        111320 *
        math.cos((a.latitude + b.latitude) * math.pi / 360);
    return math.sqrt(dx * dx + dy * dy) <= 150;
  }

  static CityWalkingRoute parseRoute(Map<String, dynamic> data) {
    if (data['code'] != 'Ok' ||
        data['routes'] is! List ||
        (data['routes'] as List).isEmpty) {
      throw const FormatException('No walking route found.');
    }
    final route = data['routes'][0];
    if (route['geometry']['type'] != 'LineString') {
      throw const FormatException('Invalid route geometry.');
    }
    final coordinates = route['geometry']['coordinates'] as List;
    if (coordinates.length < 2 || coordinates.length > 10000) {
      throw const FormatException('Invalid route length.');
    }
    final points = coordinates.map((c) {
      final p = Coordinates(
        latitude: (c[1] as num).toDouble(),
        longitude: (c[0] as num).toDouble(),
      );
      validatePoint(p);
      return p;
    }).toList();
    final duration = (route['duration'] as num).toDouble(),
        distance = (route['distance'] as num).toDouble();
    if (!duration.isFinite ||
        duration <= 0 ||
        duration > maxWalkingSeconds ||
        !distance.isFinite ||
        distance <= 0 ||
        distance > maxWalkingMeters) {
      throw const FormatException(
        'Choose a walking trip up to 50 km and twelve hours.',
      );
    }
    var geometryMeters = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      final dy = (b.latitude - a.latitude) * 111320;
      final dx =
          (b.longitude - a.longitude) *
          111320 *
          math.cos((a.latitude + b.latitude) * math.pi / 360);
      geometryMeters += math.sqrt(dx * dx + dy * dy);
    }
    if (geometryMeters <= 0 ||
        geometryMeters > maxWalkingMeters ||
        (geometryMeters - distance).abs() > math.max(10, distance * .05)) {
      throw const FormatException(
        'Walking distance does not match its mapped path.',
      );
    }
    final legs = route['legs'];
    if (legs is! List ||
        legs.isEmpty ||
        legs.any(
          (leg) => leg['steps'] is! List || (leg['steps'] as List).isEmpty,
        )) {
      throw const FormatException('Walking instructions are missing.');
    }
    List<double>? segmentSeconds;
    if (legs.any((leg) => leg['annotation'] != null)) {
      final raw = <dynamic>[];
      for (final leg in legs) {
        final annotation = leg['annotation'];
        if (annotation is! Map || annotation['duration'] is! List) {
          throw const FormatException('Walking segment timing is incomplete.');
        }
        raw.addAll(annotation['duration'] as List);
      }
      if (raw.length != points.length - 1 ||
          raw.any((v) => v is! num || !v.isFinite || v < 0)) {
        throw const FormatException('Invalid walking segment timing.');
      }
      segmentSeconds = raw.map((v) => (v as num).toDouble()).toList();
      final total = segmentSeconds.fold<double>(0, (a, b) => a + b);
      if (total <= 0 ||
          (total - duration).abs() > math.max(30, duration * .05)) {
        throw const FormatException(
          'Walking segment timing does not match the trip.',
        );
      }
    }
    final steps = <WalkingStep>[];
    double traveled = 0;
    for (final leg in legs) {
      for (final step in leg['steps'] as List? ?? const []) {
        if (step['mode'] != 'walking') {
          throw const FormatException('Provider returned a non-walking route.');
        }
        final meters = (step['distance'] as num).toDouble();
        if (!meters.isFinite || meters < 0) {
          throw const FormatException('Invalid walking instruction distance.');
        }
        final maneuver = step['maneuver'] as Map;
        final name = (step['name'] as String?)?.trim();
        final street = name == null || name.isEmpty ? 'the walking path' : name;
        final modifier = maneuver['modifier'] as String? ?? '';
        final type = maneuver['type'];
        final instruction = type == 'arrive'
            ? 'Arrive at your destination'
            : type == 'depart'
            ? 'Follow $street'
            : type == 'roundabout' || type == 'rotary'
            ? 'Follow the walking path around the roundabout'
            : modifier.isEmpty || modifier == 'straight'
            ? 'Continue on $street'
            : modifier == 'uturn'
            ? 'Turn around onto $street'
            : 'Turn $modifier onto $street';
        steps.add(
          WalkingStep(traveled * geometryMeters / distance, instruction),
        );
        traveled += meters;
      }
    }
    if (steps.isNotEmpty &&
        (traveled - distance).abs() > math.max(5, distance * .01)) {
      throw const FormatException(
        'Walking instructions do not match the route.',
      );
    }
    if (steps.last.instruction != 'Arrive at your destination') {
      throw const FormatException(
        'Walking destination instruction is missing.',
      );
    }

    for (final w in data['waypoints'] as List? ?? const []) {
      final d = w['distance'];
      if (d is! num || !d.isFinite || d < 0 || d > 150) {
        throw const FormatException(
          'Choose a point closer to a mapped walking path.',
        );
      }
    }
    return CityWalkingRoute(
      WalkingGeometry(
        points: points,
        durationSeconds: duration,
        sourceUrl: 'https://routing.openstreetmap.de/about.html',
        accessReviewed: false,
        segmentSeconds: segmentSeconds,
      ),
      distance,
      steps: steps,
    );
  }
}

Map<String, dynamic> trimBuildings(
  Map<String, dynamic> data,
  List<Coordinates> points,
) {
  final south = points.map((p) => p.latitude).reduce(math.min) - .003;
  final north = points.map((p) => p.latitude).reduce(math.max) + .003;
  final west = points.map((p) => p.longitude).reduce(math.min) - .004;
  final east = points.map((p) => p.longitude).reduce(math.max) + .004;
  return {
    ...data,
    'buildings': (data['buildings'] as List).where((b) {
      final ring = b['footprint'] as List;
      final lat = ring.map((p) => (p['latitude'] as num).toDouble()).toList()
        ..sort();
      final lon = ring.map((p) => (p['longitude'] as num).toDouble()).toList()
        ..sort();
      return lat.last >= south &&
          lat.first <= north &&
          lon.last >= west &&
          lon.first <= east;
    }).toList(),
  };
}
