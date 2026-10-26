import '../../../core/settings/route_preference.dart';

class RoutePreferenceMetric {
  const RoutePreferenceMetric(
    this.seconds, {
    this.shade,
    this.coverage,
    this.daylight = 1,
    this.timeTotals,
  });
  final double seconds, daylight;
  final double? shade, coverage;
  final Map? timeTotals;
  bool get _validTimes {
    if (timeTotals == null) return true;
    var sum = 0.0;
    for (final key in ['building', 'canopy', 'open', 'unknown', 'night']) {
      final v = timeTotals![key];
      if (v is! num || !v.isFinite || v < 0) return false;
      sum += v;
    }
    return (sum - seconds).abs() <= seconds * 1e-6 + .001;
  }

  double _time(String key) => (timeTotals![key] as num).toDouble();
  bool get comparable {
    if (!seconds.isFinite || seconds <= 0 || !_validTimes) return false;
    if (timeTotals != null) {
      final daytime = seconds - _time('night');
      return daytime <= .001 || _time('unknown') / daytime <= .10 + 1e-9;
    }
    return daylight.isFinite &&
        daylight >= 0 &&
        daylight <= 1 &&
        (daylight == 0 ||
            (shade != null &&
                shade!.isFinite &&
                shade! >= 0 &&
                shade! <= 1 &&
                coverage != null &&
                coverage!.isFinite &&
                coverage! >= .90 &&
                coverage! <= 1 &&
                shade! <= coverage! + 1e-9));
  }

  double get shadedSeconds => timeTotals != null
      ? _time('building') + _time('canopy')
      : daylight == 0
      ? 0
      : seconds * shade! * daylight;
  double get unknownSeconds => timeTotals != null
      ? _time('unknown')
      : daylight == 0
      ? 0
      : seconds * daylight * (1 - coverage!);
  double get knownSunSeconds => timeTotals != null
      ? _time('open')
      : daylight == 0
      ? 0
      : seconds * daylight * (coverage! - shade!);

  double get sunSeconds => timeTotals != null
      ? _time('open') + _time('unknown')
      : daylight == 0
      ? 0
      : seconds * daylight * (1 - shade!);
  double get nightSeconds =>
      timeTotals != null ? _time('night') : seconds * (1 - daylight);
  double get daylightShadeFraction =>
      seconds == nightSeconds ? 0 : shadedSeconds / (seconds - nightSeconds);
}

class RoutePreferenceSelection {
  const RoutePreferenceSelection(
    this.index, {
    this.shadeUnavailable = false,
    this.littleShade = false,
  });
  final int index;
  final bool shadeUnavailable, littleShade;
}

RoutePreferenceSelection selectPreferredRoute(
  RoutePreference preference,
  List<RoutePreferenceMetric> candidates,
) {
  if (candidates.isEmpty) return const RoutePreferenceSelection(0);
  final indices = List.generate(candidates.length, (i) => i);
  int compareTime(int a, int b) {
    final comparison = candidates[a].seconds.compareTo(candidates[b].seconds);
    return comparison == 0 ? a.compareTo(b) : comparison;
  }

  indices.sort(compareTime);
  final fastest = indices.first;
  if (preference == RoutePreference.fastest) {
    return RoutePreferenceSelection(fastest);
  }
  final comparable = indices.where((i) => candidates[i].comparable).toList();
  if (comparable.length < 2) {
    return RoutePreferenceSelection(fastest, shadeUnavailable: true);
  }
  if (comparable.every(
    (i) => candidates[i].nightSeconds >= candidates[i].seconds - .001,
  )) {
    return RoutePreferenceSelection(fastest);
  }
  indices
    ..clear()
    ..addAll(comparable);
  if (preference == RoutePreference.mostShade) {
    indices.sort((a, b) {
      final comparison = candidates[b].daylightShadeFraction.compareTo(
        candidates[a].daylightShadeFraction,
      );
      return comparison == 0 ? compareTime(a, b) : comparison;
    });
  } else {
    indices.removeWhere(
      (i) => candidates[i].seconds > candidates[fastest].seconds * 1.25,
    );
    if (indices.isEmpty) {
      return RoutePreferenceSelection(fastest, shadeUnavailable: true);
    }
    indices.sort((a, b) {
      double score(RoutePreferenceMetric c) =>
          c.sunSeconds + .35 * (c.shadedSeconds + c.nightSeconds);
      final comparison = score(candidates[a]).compareTo(score(candidates[b]));
      return comparison == 0 ? compareTime(a, b) : comparison;
    });
  }
  return RoutePreferenceSelection(indices.first);
}

List<int> representativeRouteIndices(List<RoutePreferenceMetric> candidates) {
  if (candidates.length <= 3) return List.generate(candidates.length, (i) => i);
  final chosen = <int>{
    for (final mode in RoutePreference.values)
      selectPreferredRoute(mode, candidates).index,
  };
  final faster = List.generate(candidates.length, (i) => i)
    ..sort((a, b) => candidates[a].seconds.compareTo(candidates[b].seconds));
  for (final i in faster) {
    if (chosen.length == 3) break;
    chosen.add(i);
  }
  return chosen.toList()..sort();
}
