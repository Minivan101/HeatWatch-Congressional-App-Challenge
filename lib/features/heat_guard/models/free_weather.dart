import '../../../core/models/coordinates.dart';
import 'weather_condition.dart';

class WeatherPlace {
  const WeatherPlace({required this.label, required this.coordinates});
  final String label;
  final Coordinates coordinates;

  static const savedArea = WeatherPlace(
    label: 'Saved Las Vegas map area',
    coordinates: Coordinates(latitude: 36.19531, longitude: -115.28587),
  );

  void validate() {
    if (label.trim().isEmpty ||
        !coordinates.latitude.isFinite ||
        !coordinates.longitude.isFinite ||
        coordinates.latitude.abs() > 90 ||
        coordinates.longitude.abs() > 180) {
      throw const FormatException('Invalid weather location');
    }
  }
}

class TimedUv {
  const TimedUv(this.validAt, this.value);
  final DateTime validAt;
  final double? value;
}

class TimedConditions {
  const TimedConditions(
    this.validAt,
    this.temperatureC,
    this.feelsLikeC,
    this.humidityPercent, {
    this.weatherCode,
    this.rainProbability,
  });
  final DateTime validAt;
  final double? temperatureC;
  final double? feelsLikeC;
  final double? humidityPercent;
  final int? weatherCode;
  final double? rainProbability;
}

class DailyConditions {
  const DailyConditions(
    this.localDate, {
    this.highC,
    this.lowC,
    this.sunrise,
    this.sunset,
  });
  final String localDate;
  final double? highC, lowC;
  final DateTime? sunrise, sunset;
}

class DailyUv {
  const DailyUv(this.localDate, this.maximum);
  final String localDate;
  final double? maximum;
}

class WeatherReading {
  const WeatherReading({
    required this.place,
    required this.gridPoint,
    required this.fetchedAt,
    required this.currentValidAt,
    required this.temperatureC,
    required this.feelsLikeC,
    required this.humidityPercent,
    required this.hourlyUv,
    required this.dailyUv,
    required this.timezone,
    required this.utcOffsetSeconds,
    required this.issues,
    this.weatherCode,
    this.isDay,
    this.hourlyConditions = const [],
    this.raw = const {},
    this.refreshAfter,
    this.mayPersist = true,
    this.sourceCheckedAt,
    this.dailyConditions = const [],
    this.windKmh,
  });

  final WeatherPlace place;
  final Coordinates gridPoint;
  final DateTime fetchedAt;
  final DateTime? currentValidAt;
  final double? temperatureC;
  final double? feelsLikeC;
  final double? humidityPercent;
  final List<TimedUv> hourlyUv;
  final List<DailyUv> dailyUv;
  final String timezone;
  final int utcOffsetSeconds;
  final List<String> issues;
  final int? weatherCode;
  final bool? isDay;
  WeatherCondition get condition =>
      WeatherCondition.fromCode(weatherCode, isDay: isDay);
  final List<TimedConditions> hourlyConditions;
  final Map<String, dynamic> raw;
  final DateTime? refreshAfter;
  final bool mayPersist;
  final DateTime? sourceCheckedAt;
  final List<DailyConditions> dailyConditions;
  final double? windKmh;

  TimedConditions? conditionsFor(DateTime at) {
    for (final value in hourlyConditions) {
      if (!at.isBefore(value.validAt) &&
          at.isBefore(value.validAt.add(const Duration(hours: 1)))) {
        return value;
      }
    }
    return null;
  }

  static final sourceUrl = Uri.parse('https://open-meteo.com/');

  TimedUv? uvFor(DateTime departure) {
    for (final sample in hourlyUv) {
      if (!departure.isBefore(sample.validAt) &&
          departure.isBefore(sample.validAt.add(const Duration(hours: 1)))) {
        return sample;
      }
    }
    return null;
  }

  bool currentFreshAt(DateTime now) =>
      currentValidAt != null &&
      _recent(currentValidAt!, now, const Duration(minutes: 30)) &&
      _recent(sourceCheckedAt ?? fetchedAt, now, const Duration(minutes: 30));

  bool forecastFreshAt(DateTime now) =>
      _recent(sourceCheckedAt ?? fetchedAt, now, const Duration(minutes: 30));

  static bool _recent(DateTime at, DateTime now, Duration limit) =>
      !at.isAfter(now.add(const Duration(minutes: 5))) &&
      now.difference(at) <= limit;
}

class NwsAlert {
  const NwsAlert({
    required this.id,
    required this.sourceUrl,
    required this.event,
    required this.headline,
    required this.description,
    required this.instruction,
    required this.senderName,
    required this.severity,
    required this.status,
    required this.messageType,
    required this.sent,
    required this.effective,
    required this.onset,
    required this.expires,
    required this.ends,
    required this.raw,
  });
  final String id;
  final Uri sourceUrl;
  final String event;
  final String? headline;
  final String? description;
  final String? instruction;
  final String senderName;
  final String severity;
  final String status;
  final String messageType;
  final DateTime sent;
  final DateTime effective;
  final DateTime? onset;
  final DateTime expires;
  final DateTime? ends;
  final Map<String, dynamic> raw;
}

class AlertReading {
  const AlertReading({
    required this.place,
    required this.fetchedAt,
    required this.providerUpdatedAt,
    required this.alerts,
    this.refreshAfter,
    this.mayPersist = true,
    this.sourceCheckedAt,
  });
  final WeatherPlace place;
  final DateTime fetchedAt;
  final DateTime? providerUpdatedAt;
  final List<NwsAlert> alerts;
  final DateTime? refreshAfter;
  final bool mayPersist;
  final DateTime? sourceCheckedAt;
  bool freshAt(DateTime now) => WeatherReading._recent(
    sourceCheckedAt ?? fetchedAt,
    now,
    const Duration(minutes: 5),
  );
}

class FreeWeatherResult {
  const FreeWeatherResult({
    required this.place,
    required this.weather,
    required this.alerts,
    required this.weatherError,
    required this.alertError,
    this.weatherFromCache = false,
    this.alertsFromCache = false,
    this.cacheNotice,
  });
  final WeatherPlace place;
  final WeatherReading? weather;
  final AlertReading? alerts;
  final String? weatherError;
  final String? alertError;
  final bool weatherFromCache;
  final bool alertsFromCache;
  final String? cacheNotice;
}
