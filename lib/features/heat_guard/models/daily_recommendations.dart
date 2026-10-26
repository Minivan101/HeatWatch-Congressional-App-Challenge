import 'dart:math' as math;

import '../services/alert_lifecycle.dart';
import 'free_weather.dart';
import 'uv_level.dart';
import 'weather_condition.dart';

class HomeRecommendation {
  const HomeRecommendation(
    this.ruleId,
    this.category,
    this.title,
    this.detail,
    this.source, {
    this.action,
    this.condition,
  });
  final String ruleId, category, title, detail, source;
  final String? action, condition;
}

const _heatSource = 'https://www.weather.gov/safety/heat-during';
const _coldSource = 'https://www.weather.gov/safety/cold-during';
const _windSource = 'https://www.weather.gov/safety/wind-during';
const _sunSource =
    'https://www.aad.org/public/everyday-care/sun-protection/shade-clothing-sunscreen/how-to-apply-sunscreen';
const _strongSunSource = 'https://www.skincancer.org/Skin-Cancer-Prevention/';

List<HomeRecommendation> recommendations(
  FreeWeatherResult? result,
  DateTime now, {
  bool imperial = true,
}) {
  final items = <HomeRecommendation>[];
  final alerts = result?.alerts;
  if (alerts != null) {
    final active = activeAlerts(alerts, now);
    if (active.isNotEmpty) {
      items.add(
        HomeRecommendation(
          'nws-active',
          'official',
          'Check the local alert',
          'Read the NWS instructions before heading out; follow any shelter or evacuation advice.',
          active.first.sourceUrl.toString(),
          condition: active.first.event,
          action: 'alert',
        ),
      );
    }
  }
  final w = result?.weather;
  if (w == null || result?.weatherError != null) return items;
  if (w.currentFreshAt(now)) {
    final weather = _weatherAdvice(w, imperial);
    if (weather != null) items.add(weather);
    final thermal = _thermalAdvice(w, imperial);
    if (thermal != null) items.add(thermal);
  }

  final night = w.currentFreshAt(now) && w.isDay == false;
  final uv = w.forecastFreshAt(now) ? _finite(w.uvFor(now)?.value) : null;
  if (!night && uv != null && uv >= 0) {
    final level = UvLevel.fromValue(uv)!;
    final title = switch (level) {
      UvLevel.low => 'Everyday sun protection',
      UvLevel.moderate => 'Use SPF 30+ outdoors',
      UvLevel.high => 'Use SPF 50+ and shade',
      UvLevel.veryHigh => 'Limit sun; use SPF 50+',
      UvLevel.extreme => 'Minimize outdoor exposure',
    };
    final extra = uv >= 11
        ? 'Move longer activities indoors; keep essential outdoor time brief. '
        : uv >= 8
        ? 'Choose shaded paths and shorten sun exposure. '
        : uv >= 6
        ? 'Favor shaded paths. '
        : '';
    final spf = uv >= 6 ? 50 : 30;
    final longerOuting = uv < 6 ? ' (50+ for longer outings)' : '';
    items.add(
      HomeRecommendation(
        'uv-${level.name}',
        'sun',
        title,
        '${extra}Use broad-spectrum, water-resistant SPF $spf+$longerOuting on exposed skin before going out. Add covering clothing, a hat + sunglasses; reapply every 2 hours outdoors and after sweating or swimming.',
        uv >= 6 ? _strongSunSource : _sunSource,
        condition: 'UV ${uv.toStringAsFixed(1)} · ${level.label}',
        action: uv >= 3 ? 'shade' : null,
      ),
    );
  }

  return List.unmodifiable(items);
}

double? _finite(double? value) => value?.isFinite == true ? value : null;
double _c(double f) => (f - 32) * 5 / 9;
bool _atLeast(double c, double f) => c >= _c(f) - 1e-9;

HomeRecommendation? _thermalAdvice(WeatherReading w, bool imperial) {
  final air = _finite(w.temperatureC), apparent = _finite(w.feelsLikeC);
  if (air == null && apparent == null) return null;

  final value = air != null && _atLeast(air, 80)
      ? math.max(air, apparent ?? air)
      : apparent ?? air!;
  final feels =
      apparent != null &&
      value == apparent &&
      (air == null || (apparent - air).abs() >= 1);
  final number = imperial ? value * 9 / 5 + 32 : value;
  var condition =
      '${feels ? 'Feels like ' : ''}${number.round()}°${imperial ? 'F' : 'C'}';
  final humidity = _finite(w.humidityPercent);
  final dry = humidity != null && humidity >= 0 && humidity <= 20;
  final humid = humidity != null && humidity >= 60 && humidity <= 100;
  if (_atLeast(value, 85) && (dry || humid)) {
    condition += ' · ${humidity.round()}% humidity';
  }
  final (band, title, detail) = switch (value) {
    _ when _atLeast(value, 115) => (
      '115-plus',
      'Postpone strenuous outings',
      'Choose air-conditioned stops and keep essential walks brief. Wear loose, light clothing; carry water and sip regularly.',
    ),
    _ when _atLeast(value, 105) => (
      '105-114',
      'Limit outdoor time',
      'Keep walks short with air-conditioned breaks. Wear loose, light clothing; carry water and drink regularly.',
    ),
    _ when _atLeast(value, 95) => (
      '95-104',
      'Short walks + cooling breaks',
      'Wear lightweight, loose clothing. Carry water, drink regularly and plan an air-conditioned stop.',
    ),
    _ when _atLeast(value, 85) => (
      '85-94',
      'Carry water + take shade',
      'Wear light, breathable clothing. Sip water regularly and take shaded breaks during longer walks.',
    ),
    _ when _atLeast(value, 75) => (
      '75-84',
      'Keep your outfit light',
      'Choose a breathable top and light bottoms. Bring water for longer outings.',
    ),
    _ when _atLeast(value, 65) => (
      '65-74',
      'Choose light layers',
      'Try a T-shirt or light long sleeve. Bring a thin layer for shaded stops or cool indoor spaces.',
    ),
    _ when _atLeast(value, 55) => (
      '55-64',
      'Bring a light jacket',
      'A light jacket or long sleeve with long pants helps on cooler walks. Use a wind-resistant layer if it feels breezy.',
    ),
    _ when _atLeast(value, 45) => (
      '45-54',
      'Wear a jacket + layers',
      'Layer a jacket over a long sleeve with long pants. Keep an extra layer for time spent standing outside.',
    ),
    _ when value > _c(32) => (
      '33-44',
      'Bundle up for the cold',
      'Wear a warm coat, layers and covered shoes. Add a hat and gloves for longer walks; stay dry and out of the wind.',
    ),
    _ => (
      'freezing',
      'Cover up + warm up indoors',
      'Wear a warm coat, hat, gloves and layers. Keep skin covered, stay dry and take indoor warming breaks.',
    ),
  };
  final extra = _atLeast(value, 85)
      ? dry
            ? ' Sweat can dry quickly in Vegas; do not wait for thirst.'
            : humid
            ? ' Humidity makes it harder for sweat to cool you.'
            : ''
      : '';
  return HomeRecommendation(
    'thermal-$band',
    _atLeast(value, 85) ? 'cooling' : 'clothing',
    title,
    '$detail$extra',
    _atLeast(value, 75) ? _heatSource : _coldSource,
    condition: condition,
    action: _atLeast(value, 95) ? 'cool' : null,
  );
}

HomeRecommendation? _weatherAdvice(WeatherReading w, bool imperial) {
  final sky = w.condition.sky, code = w.weatherCode;
  String? title, detail, id, category;
  var source = 'https://www.weather.gov/safety/flood-during';
  if (sky == WeatherSky.thunderstorm) {
    id = 'storm';
    category = 'storm';
    title = 'Pause outdoor plans';
    detail = 'Use a sturdy building for shelter. If you hear thunder, stay inside until 30 minutes after the last rumble; an open shade shelter is not protection.';
    source = 'https://www.weather.gov/safety/lightning-tips';
  } else if ([56, 57, 66, 67].contains(code)) {
    id = 'ice';
    category = 'rain';
    title = 'Watch for icy surfaces';
    detail = 'Wear a waterproof outer layer and grippy shoes. Avoid slippery ramps, steps and bridges; postpone the walk if paths are icy.';
    source = _coldSource;
  } else if (sky == WeatherSky.rain || sky == WeatherSky.drizzle) {
    id = 'rain';
    category = 'rain';
    title = 'Pack a light rain shell';
    detail = 'Use shoes with grip. Avoid washes and low crossings; never walk through floodwater.';
  } else if (sky == WeatherSky.snow) {
    id = 'snow';
    category = 'rain';
    title = 'Keep warm + watch your footing';
    detail = 'Use a waterproof outer layer and grippy shoes. Watch for ice on shaded paths and bridges.';
    source = _coldSource;
  } else if (sky == WeatherSky.fog) {
    id = 'fog';
    category = 'weather';
    title = 'Stay visible at crossings';
    detail = 'Wear bright or reflective clothing. Use marked crossings and make sure drivers have seen you.';
    source = 'https://www.weather.gov/safety/fog';
  }
  final wind = _finite(w.windKmh);
  final mph = wind == null || wind < 0 ? null : wind / 1.609344;
  if (title != null) {
    final strongWind = mph != null && mph >= 30;
    return HomeRecommendation(
      'conditions-$id',
      category!,
      title,
      '$detail${strongWind ? ' Strong wind: avoid trees and loose debris.' : ''}',
      source,
      condition: w.condition.label,
    );
  }
  if (mph == null || mph < 12 - 1e-9) return null;
  final (band, windTitle, windDetail) = switch (mph) {
    >= 40 => (
      '40-plus',
      'Delay exposed walks',
      'Choose sturdy indoor shelter; stay away from trees, power lines and loose debris. Go indoors if blowing dust reduces visibility.',
    ),
    >= 30 => (
      '30-39',
      'Head for sheltered places',
      'Avoid exposed paths, trees and loose debris. Blowing dust is possible; go inside if visibility drops.',
    ),
    >= 20 => (
      '20-29',
      'Choose a sheltered walk',
      'Secure hats and loose items. Favor sheltered paths and watch for windblown debris.',
    ),
    _ => (
      '12-19',
      'Prepare for a breezy walk',
      'Secure your hat and loose items. A wind-resistant layer helps if you feel cool.',
    ),
  };
  final speed = imperial ? mph : wind!;
  return HomeRecommendation(
    'wind-$band',
    'wind',
    windTitle,
    windDetail,
    _windSource,
    condition: 'Wind ${speed.round()} ${imperial ? 'mph' : 'km/h'}',
  );
}
