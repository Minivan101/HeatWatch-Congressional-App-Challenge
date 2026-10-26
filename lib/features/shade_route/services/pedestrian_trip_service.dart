import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'walking_limits.dart';
import 'walking_request_policy.dart';
import '../../../core/models/coordinates.dart';
import 'city_trip_service.dart';
import 'local_shade_calculator.dart';
import 'walking_navigation.dart';

// walking paths
class PedestrianTripService extends CityTripService {
  PedestrianTripService({super.client, super.now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  DateTime? _mapRetryAt;
  final _areas =
      <({List<double> bounds, Map<String, dynamic> data, DateTime fetched})>[];
  Future<void> _pending = Future.value();
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<List<CityWalkingRoute>> walkAlternatives(
    Coordinates start,
    Coordinates end, {
    List<Coordinates> via = const [],
  }) async {
    final points = [start, ...via, end];
    if (via.length > 6) {
      throw const FormatException('Use at most six intermediate points.');
    }
    points.forEach(CityTripService.validatePoint);
    return _mappedAlternatives(points);
  }

  Future<List<CityWalkingRoute>> _mappedAlternatives(
    List<Coordinates> points, {
    bool expanded = false,
  }) async {
    final start = points.first, end = points.last;
    final via = points.skip(1).take(points.length - 2).toList();
    final scale = expanded ? 3 : 1;
    final south = points.map((p) => p.latitude).reduce(math.min) - .004 * scale;
    final north = points.map((p) => p.latitude).reduce(math.max) + .004 * scale;
    final west = points.map((p) => p.longitude).reduce(math.min) - .005 * scale;
    final east = points.map((p) => p.longitude).reduce(math.max) + .005 * scale;

    final directMeters = [
      for (var i = 1; i < points.length; i++)
        walkingDistance(points[i - 1], points[i]),
    ].fold<double>(0, (a, b) => a + b);
    if (directMeters > maxWalkingMeters) {
      throw const FormatException('Choose a walking trip up to 50 km.');
    }
    if ((north - south) * (east - west) > .012 || directMeters > 6000) {
      return super.walkAlternatives(start, end, via: via);
    }
    Map<String, dynamic>? data;
    for (final area in _areas.reversed) {
      if (_now().difference(area.fetched).inMinutes < 30 &&
          (!expanded ||
              (area.bounds[0] <= south &&
                  area.bounds[1] <= west &&
                  area.bounds[2] >= north &&
                  area.bounds[3] >= east)) &&
          points.every(
            (p) =>
                p.latitude > area.bounds[0] + .001 &&
                p.longitude > area.bounds[1] + .001 &&
                p.latitude < area.bounds[2] - .001 &&
                p.longitude < area.bounds[3] - .001,
          )) {
        data = area.data;
        break;
      }
    }
    if (data == null) {
      try {
        if (_mapRetryAt?.isAfter(_now()) == true) {
          throw const FormatException(
            'Pedestrian map service is temporarily busy.',
          );
        }

        late http.Response response;
        final request = _pending.then((_) async {
          if (_mapRetryAt?.isAfter(_now()) == true) {
            throw const FormatException(
              'Pedestrian map service is temporarily busy.',
            );
          }
          final delay = 5000 - _now().difference(_lastRequest).inMilliseconds;
          if (delay > 0) {
            await Future<void>.delayed(Duration(milliseconds: delay));
          }
          _lastRequest = _now();
          final bbox = '$south,$west,$north,$east';
          response = await client
              .post(
                Uri.https('overpass-api.de', '/api/interpreter'),
                headers: {
                  'User-Agent': 'HeatWatch/0.1 (com.ivantrac.heatwatch student prototype)',
                },
                body: {
                  'data':
                      '[out:json][timeout:25][maxsize:16777216];'
                      'way["highway"~"^(footway|path|pedestrian|steps|cycleway|residential|service|unclassified|living_street|tertiary|tertiary_link|secondary|secondary_link|primary|primary_link|trunk|trunk_link|motorway|motorway_link)\$"]($bbox);'
                      'out body;>;out body qt;',
                },
              )
              .timeout(const Duration(seconds: 35));
          if (response.statusCode == 429 || response.statusCode == 503) {
            _mapRetryAt =
                walkingRetryTime(response.headers['retry-after'], _now()) ??
                _now().add(const Duration(seconds: 30));
          }
          if (response.statusCode != 200 ||
              response.bodyBytes.length > 8 * 1024 * 1024) {
            throw const FormatException(
              'Pedestrian map unavailable. Try again later.',
            );
          }
        });
        _pending = request.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        await request;
        data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['remark'] != null || data['elements'] is! List) {
          throw const FormatException(
            'Pedestrian map query incomplete. Try again later.',
          );
        }
        if (_areas.length >= 3) _areas.removeAt(0);
        _areas.add((
          bounds: [south, west, north, east],
          data: data,
          fetched: _now(),
        ));
      } catch (_) {
        if (_mapRetryAt?.isAfter(_now()) != true) {
          _mapRetryAt = _now().add(const Duration(seconds: 30));
        }
        if (expanded) {
          throw const FormatException(
            'Expanded walking map unavailable. Try again later.',
          );
        }

        return super.walkAlternatives(start, end, via: via);
      }
    }
    try {
      return await compute(_calculatePedestrianRoutes, (data, points));
    } on FormatException catch (e) {
      final mappingGap =
          e.message.startsWith('No connected walking route') ||
          e.message.startsWith('No walking network within');
      if (mappingGap && _restrictedWayNear(data, points)) {
        throw const FormatException(
          'This point may be on a private road. Choose a nearby public road '
          'or accessible entrance on the map.',
        );
      }
      final expandedArea = (north - south + .016) * (east - west + .020);
      if (!expanded && expandedArea <= .012 && mappingGap) {
        return _mappedAlternatives(points, expanded: true);
      }
      if (mappingGap) {
        try {
          return await super.walkAlternatives(start, end, via: via);
        } on FormatException {
          throw const FormatException(
            'No public walking route was found. Choose a nearby public road '
            'or accessible entrance on the map.',
          );
        }
      }
      rethrow;
    }
  }

  bool _restrictedWayNear(Map<String, dynamic> data, List<Coordinates> points) {
    final elements = data['elements'];
    if (elements is! List) return false;
    final nodes = <int, Coordinates>{};
    for (final element in elements) {
      if (element is! Map || element['type'] != 'node') continue;
      final id = element['id'], lat = element['lat'], lon = element['lon'];
      if (id is int && lat is num && lon is num) {
        nodes[id] = Coordinates(
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
        );
      }
    }
    for (final element in elements) {
      if (element is! Map || element['type'] != 'way') continue;
      final tags = element['tags'];
      if (tags is! Map || PedestrianGraph._publicAccess(tags)) continue;
      final ids = element['nodes'];
      if (ids is! List) continue;
      for (var i = 1; i < ids.length; i++) {
        final a = nodes[ids[i - 1]], b = nodes[ids[i]];
        if (a == null || b == null) continue;
        if (points.any((point) => projectToWalk(point, a, b).distance <= 160)) {
          return true;
        }
      }
    }
    return false;
  }
}

List<CityWalkingRoute> _calculatePedestrianRoutes(
  (Map<String, dynamic>, List<Coordinates>) input,
) => PedestrianGraph(input.$1, inferStreetWalking: true).routes(input.$2);

class _Edge {
  const _Edge(this.to, this.meters, this.name, this.kind);
  final int to;
  final double meters;
  final String name, kind;
}

class PedestrianGraph {
  PedestrianGraph(
    Map<String, dynamic> data, {
    this.inferStreetWalking = false,
  }) {
    final elements = data['elements'];
    if (elements is! List || elements.length > 80000) {
      throw const FormatException('Invalid pedestrian map.');
    }
    final blocked = <int>{};
    final crossingNodes = <int>{};
    for (final raw in elements.whereType<Map>()) {
      if (raw['type'] != 'node') continue;
      final id = raw['id'] as int;
      final p = Coordinates(
        latitude: (raw['lat'] as num).toDouble(),
        longitude: (raw['lon'] as num).toDouble(),
      );
      if (!p.latitude.isFinite ||
          !p.longitude.isFinite ||
          p.latitude.abs() > 90 ||
          p.longitude.abs() > 180) {
        continue;
      }
      _points[id] = p;
      final tags = (raw['tags'] as Map?) ?? {};
      if (tags['highway'] == 'crossing' && tags['crossing'] != 'no') {
        crossingNodes.add(id);
      }
      if (!_publicAccess(tags) ||
          tags['barrier'] == 'wall' ||
          tags['barrier'] == 'fence' ||
          tags['barrier'] == 'block' ||
          tags['locked'] == 'yes') {
        blocked.add(id);
      }
    }

    for (final raw in elements.whereType<Map>()) {
      if (raw['type'] != 'way') continue;
      final tags = (raw['tags'] as Map?) ?? {};
      if ({
        'residential',
        'service',
        'unclassified',
        'living_street',
        'tertiary',
        'tertiary_link',
        'secondary',
        'secondary_link',
        'primary',
        'primary_link',
        'trunk',
        'trunk_link',
        'motorway',
        'motorway_link',
      }.contains(tags['highway'])) {
        final ids = (raw['nodes'] as List).cast<int>();
        for (var i = 0; i < ids.length - 1; i++) {
          final a = _points[ids[i]], b = _points[ids[i + 1]];
          if (a != null && b != null) _indexRoad(a, b, tags);
        }
      }
    }
    for (final raw in elements.whereType<Map>()) {
      if (raw['type'] != 'way') continue;
      final tags = (raw['tags'] as Map?) ?? {};
      final highway = tags['highway'];
      final street = inferStreetWalking && _walkableStreet(tags);
      if (!street &&
              !{
                'footway',
                'path',
                'pedestrian',
                'steps',
                'cycleway',
              }.contains(highway) ||
          !_publicAccess(tags) ||
          tags['area'] == 'yes' ||
          tags['construction'] != null ||
          tags['proposed'] != null ||
          tags['crossing'] == 'no' ||
          (highway == 'cycleway' &&
              !{'yes', 'designated', 'permissive'}.contains(tags['foot']))) {
        continue;
      }
      final ids = (raw['nodes'] as List).cast<int>();
      final kind = street
          ? 'inferred_street'
          : tags['footway'] == 'crossing'
          ? 'crossing'
          : tags['footway'] == 'sidewalk'
          ? 'sidewalk'
          : highway == 'steps'
          ? 'steps'
          : 'path';
      final name =
          (tags['name'] as String?) ??
          switch (kind) {
            'crossing' => 'the pedestrian crossing',
            'sidewalk' => 'the sidewalk',
            'steps' => 'the steps',
            'inferred_street' => 'the street',
            _ => 'the walking path',
          };
      for (var i = 0; i < ids.length - 1; i++) {
        final a = ids[i], b = ids[i + 1];
        if (!_points.containsKey(a) ||
            !_points.containsKey(b) ||
            blocked.contains(a) ||
            blocked.contains(b)) {
          continue;
        }
        if (!street &&
            kind != 'crossing' &&
            _crossesRoad(_points[a]!, _points[b]!, tags, [
              if (crossingNodes.contains(a)) _points[a]!,
              if (crossingNodes.contains(b)) _points[b]!,
            ])) {
          continue;
        }
        final meters = walkingDistance(_points[a]!, _points[b]!);
        if (meters <= 0 || !meters.isFinite) continue;
        if (tags['oneway:foot'] != '-1') _add(a, _Edge(b, meters, name, kind));
        if (tags['oneway:foot'] != 'yes' && tags['oneway:foot'] != '1') {
          _add(b, _Edge(a, meters, name, kind));
        }
      }
    }
  }
  final bool inferStreetWalking;
  double get _snapLimit => inferStreetWalking ? 150 : 40;
  static bool _walkableStreet(Map tags) =>
      {
        'residential',
        'living_street',
        'unclassified',
        'service',
        'tertiary',
        'secondary',
        'primary',
      }.contains(tags['highway']) &&
      tags['motorroad'] != 'yes' &&
      tags['expressway'] != 'yes' &&
      tags['sidewalk'] != 'no' &&
      tags['sidewalk'] != 'none' &&
      tags['service'] != 'driveway';

  final _points = <int, Coordinates>{};
  final _edges = <int, List<_Edge>>{};
  int _virtual = -1;
  final _roadGrid =
      <String, List<({Coordinates a, Coordinates b, Map tags})>>{};
  Iterable<String> _cells(Coordinates a, Coordinates b) sync* {
    final x0 = (math.min(a.longitude, b.longitude) * 500).floor();
    final x1 = (math.max(a.longitude, b.longitude) * 500).floor();
    final y0 = (math.min(a.latitude, b.latitude) * 500).floor();
    final y1 = (math.max(a.latitude, b.latitude) * 500).floor();
    if ((x1 - x0 + 1) * (y1 - y0 + 1) > 1000) {
      throw const FormatException(
        'Pedestrian map contains an oversized segment.',
      );
    }
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        yield '$x/$y';
      }
    }
  }

  void _indexRoad(Coordinates a, Coordinates b, Map tags) {
    final road = (a: a, b: b, tags: tags);
    for (final cell in _cells(a, b)) {
      (_roadGrid[cell] ??= []).add(road);
    }
  }

  bool _crossesRoad(
    Coordinates a,
    Coordinates b,
    Map tags,
    List<Coordinates> crossings,
  ) {
    for (final cell in _cells(a, b)) {
      for (final road in _roadGrid[cell] ?? []) {
        if ((tags['layer'] ?? '0') != (road.tags['layer'] ?? '0') ||
            (tags['bridge'] == 'yes') != (road.tags['bridge'] == 'yes') ||
            (tags['tunnel'] == 'yes') != (road.tags['tunnel'] == 'yes')) {
          continue;
        }
        final rx = b.longitude - a.longitude, ry = b.latitude - a.latitude;
        final sx = road.b.longitude - road.a.longitude,
            sy = road.b.latitude - road.a.latitude;
        final qx = road.a.longitude - a.longitude,
            qy = road.a.latitude - a.latitude;
        final cross = rx * sy - ry * sx;
        if (cross.abs() < 1e-14) {
          if (projectToWalk(a, road.a, road.b).distance < .5 ||
              projectToWalk(b, road.a, road.b).distance < .5) {
            return true;
          }
          continue;
        }
        final t = (qx * sy - qy * sx) / cross, u = (qx * ry - qy * rx) / cross;
        if (t < -1e-8 || t > 1 + 1e-8 || u < -1e-8 || u > 1 + 1e-8) continue;
        final point = Coordinates(
          latitude: a.latitude + ry * t,
          longitude: a.longitude + rx * t,
        );
        if (!crossings.any((p) => walkingDistance(p, point) < 1)) return true;
      }
    }
    return false;
  }

  static bool _publicAccess(Map tags) {
    if (tags.keys.any((k) => k.toString().endsWith(':conditional')) ||
        tags['indoor'] == 'yes' ||
        tags['opening_hours'] != null) {
      return false;
    }
    final foot = tags['foot'];
    if (foot != null && !{'yes', 'designated', 'permissive'}.contains(foot)) {
      return false;
    }
    if (!{'yes', 'designated', 'permissive'}.contains(foot) &&
        tags['access'] != null &&
        !{'yes', 'designated', 'permissive'}.contains(tags['access'])) {
      return false;
    }
    return true;
  }

  void _add(int from, _Edge edge) => (_edges[from] ??= []).add(edge);

  int _snap(Coordinates p, Map<int, int> components, int component) {
    double best = double.infinity;
    int? from;
    _Edge? chosen;
    Coordinates? projected;
    for (final entry in _edges.entries) {
      if (components[entry.key] != component) continue;
      for (final edge in entry.value) {
        final q = projectToWalk(p, _points[entry.key]!, _points[edge.to]!);
        if (q.distance < best) {
          best = q.distance;
          from = entry.key;
          chosen = edge;
          projected = q.point;
        }
      }
    }
    if (from == null || chosen == null || best > _snapLimit) {
      throw FormatException(
        'Choose a point within ${_snapLimit.round()} m of the walking network.',
      );
    }
    final a = from, b = chosen.to;
    if (walkingDistance(projected!, _points[a]!) < .1) return a;
    if (walkingDistance(projected, _points[b]!) < .1) return b;
    final id = _virtual--;
    _points[id] = projected;
    components[id] = component;
    final forward = _edges[a]!.where((e) => e.to == b).toList();
    final reverse = (_edges[b] ?? []).where((e) => e.to == a).toList();
    _edges[a]!.removeWhere((e) => e.to == b);
    _edges[b]?.removeWhere((e) => e.to == a);
    for (final e in forward) {
      _add(
        a,
        _Edge(id, walkingDistance(_points[a]!, projected), e.name, e.kind),
      );
      _add(
        id,
        _Edge(b, walkingDistance(projected, _points[b]!), e.name, e.kind),
      );
    }
    for (final e in reverse) {
      _add(
        b,
        _Edge(id, walkingDistance(_points[b]!, projected), e.name, e.kind),
      );
      _add(
        id,
        _Edge(a, walkingDistance(projected, _points[a]!), e.name, e.kind),
      );
    }
    return id;
  }

  List<int> _shortest(
    int start,
    int end,
    Set<String> penalty, {
    Set<String> excludedEdges = const {},
    Set<int> excludedNodes = const {},
  }) {
    final distances = <int, double>{start: 0};
    final previous = <int, int>{};
    final queue = _Heap()..add((0, start));
    while (queue.isNotEmpty) {
      final (cost, node) = queue.remove();
      if (cost > distances[node]!) continue;
      if (node == end) {
        final path = <int>[end];
        while (path.last != start) {
          path.add(previous[path.last]!);
        }
        return path.reversed.toList();
      }
      for (final edge in _edges[node] ?? <_Edge>[]) {
        if (excludedNodes.contains(edge.to) ||
            excludedEdges.contains(_key(node, edge.to))) {
          continue;
        }
        final score =
            cost +
            edge.meters * (penalty.contains(_key(node, edge.to)) ? 2.5 : 1);
        if (score < (distances[edge.to] ?? double.infinity)) {
          distances[edge.to] = score;
          previous[edge.to] = node;
          queue.add((score, edge.to));
        }
      }
    }
    throw const FormatException(
      'No connected walking route is available between these points. Try a nearby entrance.',
    );
  }

  String _key(int a, int b) => a < b ? '$a/$b' : '$b/$a';

  CityWalkingRoute _routeForPath(List<int> path) {
    double distance = 0, inferredStreetMeters = 0;
    final steps = <WalkingStep>[];
    for (var i = 0; i < path.length - 1; i++) {
      final edge = _edges[path[i]]!.firstWhere((e) => e.to == path[i + 1]);
      if (i == 0 ||
          edge.kind == 'crossing' &&
              _edges[path[i - 1]]!.firstWhere((e) => e.to == path[i]).kind !=
                  'crossing') {
        steps.add(
          WalkingStep(
            distance,
            edge.kind == 'crossing'
                ? 'Use ${edge.name}'
                : 'Follow ${edge.name}',
          ),
        );
      } else if (i > 0) {
        final turn =
            (walkingBearing(_points[path[i]]!, _points[path[i + 1]]!) -
                    walkingBearing(_points[path[i - 1]]!, _points[path[i]]!) +
                    540) %
                360 -
            180;
        if (turn.abs() >= 35) {
          steps.add(
            WalkingStep(
              distance,
              'Turn ${turn > 0 ? 'right' : 'left'} onto ${edge.name}',
            ),
          );
        }
      }
      distance += edge.meters;
      if (edge.kind == 'inferred_street') {
        inferredStreetMeters += edge.meters;
      }
    }
    steps.add(WalkingStep(distance, 'Arrive at your destination'));
    return CityWalkingRoute(
      WalkingGeometry(
        points: path.map((i) => _points[i]!).toList(),
        durationSeconds: distance / 1.4,
        sourceUrl: 'https://www.openstreetmap.org',
        accessReviewed: false,
      ),
      distance,
      steps: steps,
      inferredStreetMeters: inferredStreetMeters,
    );
  }

  Iterable<List<int>> _branchPaths(List<int> base) sync* {
    final branches = [
      for (var i = 0; i < base.length - 1; i++)
        if ((_edges[base[i]] ?? []).any(
          (e) => e.to != base[i + 1] && (i == 0 || e.to != base[i - 1]),
        ))
          i,
    ];
    final count = math.min(12, branches.length);
    for (var n = 0; n < count; n++) {
      final i = branches[(n * branches.length / count).floor()];
      final root = base.take(i + 1).toList();
      try {
        final tail = _shortest(
          root.last,
          base.last,
          {},
          excludedEdges: {_key(base[i], base[i + 1])},
          excludedNodes: root.take(root.length - 1).toSet(),
        );
        yield [...root, ...tail.skip(1)];
      } on FormatException {
        // no alternate path here
      }
    }
  }

  List<CityWalkingRoute> routes(List<Coordinates> endpoints) {
    if (endpoints.length < 2 || endpoints.length > 8) {
      throw const FormatException('Choose a start and destination.');
    }
    final neighbours = <int, Set<int>>{};
    for (final entry in _edges.entries) {
      for (final edge in entry.value) {
        (neighbours[entry.key] ??= {}).add(edge.to);
        (neighbours[edge.to] ??= {}).add(entry.key);
      }
    }
    final components = <int, int>{};
    var component = 0;
    for (final node in neighbours.keys) {
      if (components.containsKey(node)) continue;
      final pending = [node];
      components[node] = component;
      while (pending.isNotEmpty) {
        for (final next in neighbours[pending.removeLast()] ?? <int>{}) {
          if (!components.containsKey(next)) {
            components[next] = component;
            pending.add(next);
          }
        }
      }
      component++;
    }
    final nearby = <Map<int, double>>[];
    for (final p in endpoints) {
      final distances = <int, double>{};
      for (final entry in _edges.entries) {
        final c = components[entry.key]!;
        for (final edge in entry.value) {
          final distance = projectToWalk(
            p,
            _points[entry.key]!,
            _points[edge.to]!,
          ).distance;
          if (distance <= _snapLimit &&
              distance < (distances[c] ?? double.infinity)) {
            distances[c] = distance;
          }
        }
      }
      if (distances.isEmpty) {
        throw FormatException(
          'No walking network within ${_snapLimit.round()} m of a trip point. '
          'Choose a nearby street or entrance on the map.',
        );
      }
      nearby.add(distances);
    }
    final common =
        nearby.first.keys
            .where((c) => nearby.every((v) => v.containsKey(c)))
            .toList()
          ..sort(
            (a, b) => nearby
                .fold<double>(0, (sum, v) => sum + v[a]!)
                .compareTo(nearby.fold<double>(0, (sum, v) => sum + v[b]!)),
          );
    List<int>? ids;
    for (final c in common.take(8)) {
      final candidate = endpoints.map((p) => _snap(p, components, c)).toList();
      try {
        for (var i = 0; i < candidate.length - 1; i++) {
          _shortest(candidate[i], candidate[i + 1], {});
        }
        ids = candidate;
        break;
      } on FormatException {
        // try the next group
      }
    }
    if (ids == null) {
      throw const FormatException(
        'No connected walking route is available between these points. '
        'Choose a nearby entrance.',
      );
    }
    final paths = <List<int>>[];
    final seen = <String>{}, penalty = <String>{};
    for (var attempt = 0; attempt < 6; attempt++) {
      final path = <int>[];
      for (var i = 0; i < ids.length - 1; i++) {
        final leg = _shortest(ids[i], ids[i + 1], penalty);
        path.addAll(i == 0 ? leg : leg.skip(1));
      }
      if (!seen.add(path.join(','))) break;
      paths.add(path);
      for (var i = 1; i < path.length; i++) {
        penalty.add(_key(path[i - 1], path[i]));
      }
    }

    if (ids.length == 2 && paths.isNotEmpty) {
      for (final branch in _branchPaths(paths.first)) {
        if (seen.add(branch.join(','))) paths.add(branch);
        if (paths.length >= 10) break;
      }
    }
    final routes =
        paths
            .map(_routeForPath)
            .where(
              (r) =>
                  r.distanceMeters > 0 &&
                  r.distanceMeters <= maxWalkingMeters &&
                  r.geometry.points.length <= 10000,
            )
            .toList()
          ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    if (routes.isNotEmpty) {
      routes.removeWhere(
        (r) => r.distanceMeters > routes.first.distanceMeters * 1.7,
      );
      if (routes.length > 8) routes.removeRange(8, routes.length);
    }
    if (routes.isEmpty) {
      throw const FormatException('Choose a pedestrian trip up to 50 km.');
    }
    return routes;
  }
}

class _Heap {
  final _items = <(double, int)>[];
  bool get isNotEmpty => _items.isNotEmpty;
  void add((double, int) item) {
    _items.add(item);
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_items[parent].$1 <= item.$1) break;
      _items[i] = _items[parent];
      i = parent;
    }
    _items[i] = item;
  }

  (double, int) remove() {
    final first = _items.first, last = _items.removeLast();
    if (_items.isEmpty) return first;
    var i = 0;
    while (i * 2 + 1 < _items.length) {
      var child = i * 2 + 1;
      if (child + 1 < _items.length &&
          _items[child + 1].$1 < _items[child].$1) {
        child++;
      }
      if (_items[child].$1 >= last.$1) break;
      _items[i] = _items[child];
      i = child;
    }
    _items[i] = last;
    return first;
  }
}
