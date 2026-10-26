class OfficialCoolingDirectory {
  OfficialCoolingDirectory._(this.data);

  final Map<String, dynamic> data;
  int get revision => data['revision'] as int;
  List<Map<String, dynamic>> get stations =>
      (data['stations'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get sources =>
      (data['sources'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic> source(String id) =>
      sources.singleWhere((source) => source['id'] == id);

  static OfficialCoolingDirectory parse(Object? value) {
    void require(bool condition) {
      if (!condition) {
        throw const FormatException('Invalid official cooling directory');
      }
    }

    require(value is Map<String, dynamic>);
    final data = value as Map<String, dynamic>;
    require(data['schemaVersion'] == 1 && data['revision'] is int);
    require((data['revision'] as int) > 0);
    require(
      data['datasetId'] is String && (data['datasetId'] as String).isNotEmpty,
    );
    require(_date(data['checkedOn']) != null);
    require(data['timeZoneId'] == 'America/Los_Angeles');
    require(data['sources'] is List && data['stations'] is List);
    final sources = data['sources'] as List;
    final stations = data['stations'] as List;
    require(sources.isNotEmpty && stations.isNotEmpty);
    final sourceIds = <String>{};
    for (final source in sources) {
      require(source is Map<String, dynamic>);
      final s = source as Map<String, dynamic>;
      require(s['id'] is String && (s['id'] as String).isNotEmpty);
      require(sourceIds.add(s['id'] as String));
      require(_https(s['url']) && _date(s['retrievedOn']) != null);
      require(s['hostingProvenance'] is String && s['language'] is String);
      require(
        s['publicationDate'] == null || _date(s['publicationDate']) != null,
      );
      require(_period(s['activationStart'], s['activationEnd']));
      if (s['qrLinks'] != null) {
        require(s['qrLinks'] is List);
        for (final link in s['qrLinks'] as List) {
          require(
            link is Map &&
                link['sourceId'] == s['id'] &&
                _https(link['payload']) &&
                _https(link['resolvedUrl']) &&
                link['sourcePage'] is int &&
                link['sourcePage'] > 0 &&
                link['context'] is String &&
                link['visuallyReviewed'] == true &&
                link['sourceSha256'] is String &&
                RegExp(r'^[a-f0-9]{64}$').hasMatch(link['sourceSha256']),
          );
        }
      }
      if (s['context'] != null) {
        require(s['context'] is Map);
        final context = s['context'] as Map;
        require(
          context['activationCautionAsDisplayed'] is String &&
              context['availabilityCautionAsDisplayed'] is String &&
              context['legendAsDisplayed'] is List &&
              (context['legendAsDisplayed'] as List).every(
                (line) => line is String,
              ),
        );
      }
    }
    var assertions = 0;
    var located = 0;
    final ids = <String>{};
    for (final station in stations) {
      require(station is Map<String, dynamic>);
      final s = station as Map<String, dynamic>;
      for (final key in ['id', 'name', 'address', 'phone']) {
        require(s[key] is String && (s[key] as String).trim().isNotEmpty);
      }
      require(ids.add(s['id'] as String));

      require(s['currentOpenStatus'] == 'unknown');
      require(s['accessibility'] == null && s['waterAvailable'] == null);
      require(
        s['reviewNotes'] is List &&
            (s['reviewNotes'] as List).every((note) => note is String),
      );
      if (s['addressEvidence'] != null) {
        require(s['addressEvidence'] is List);
        for (final evidence in s['addressEvidence'] as List) {
          require(
            evidence is Map &&
                evidence['stationId'] == s['id'] &&
                _https(evidence['sourceUrl']) &&
                _date(evidence['retrievedOn']) != null &&
                evidence['addressAsPublished'] is String &&
                evidence['scope'] is String &&
                evidence['sha256'] is String &&
                RegExp(r'^[a-f0-9]{64}$').hasMatch(evidence['sha256']),
          );
        }
      }
      if (s['phoneProvenance'] != null) {
        final contact = s['phoneProvenance'];
        require(
          contact is Map &&
              _https(contact['sourceUrl']) &&
              _date(contact['checkedOn']) != null &&
              contact['scope'] is String,
        );
      }
      final location = s['coordinates'];
      require(s['coordinateReview'] is Map);
      final coordinateReview = s['coordinateReview'] as Map;
      require(
        location == null
            ? coordinateReview['status'] == 'unresolved'
            : [
                'address-matched',
                'source-matched',
              ].contains(coordinateReview['status']),
      );
      require(coordinateReview['candidates'] is List);
      for (final candidate in coordinateReview['candidates'] as List) {
        require(
          candidate is Map &&
              candidate['name'] is String &&
              candidate['address'] is String &&
              candidate['objectId'] is int,
        );
      }
      if (location != null) {
        require(location is Map<String, dynamic>);
        final point = location as Map<String, dynamic>;
        final lat = point['latitude'];
        final lon = point['longitude'];
        require(lat is num && lat.isFinite && lat >= -90 && lat <= 90);
        require(lon is num && lon.isFinite && lon >= -180 && lon <= 180);
        require(
          _https(point['sourceUrl']) && _date(point['checkedOn']) != null,
        );
        require(
          point['precision'] is String &&
              (point['objectId'] is int || point['featureId'] is String),
        );
        require(
          point['sourceName'] is String &&
              (point['sourceAddress'] is String ||
                  (point['sourceAddress'] == null &&
                      coordinateReview['status'] == 'source-matched')),
        );
        located++;
      }
      require(s['assertions'] is List && (s['assertions'] as List).isNotEmpty);
      final assertionSources = <String>{};
      for (final assertion in s['assertions'] as List) {
        require(assertion is Map<String, dynamic>);
        final a = assertion as Map<String, dynamic>;
        require(a['stationId'] == s['id']);
        require(a['sourceId'] is String && sourceIds.contains(a['sourceId']));
        require(assertionSources.add(a['sourceId'] as String));
        require(a['currentOpenStatus'] == 'unknown');
        require(_period(a['activationStart'], a['activationEnd']));
        final source = sources.singleWhere(
          (source) => source['id'] == a['sourceId'],
        );
        require(
          a['activationStart'] == source['activationStart'] &&
              a['activationEnd'] == source['activationEnd'],
        );
        require(
          (a['rawText'] is String && (a['rawText'] as String).isNotEmpty) ||
              (a['rawPanelText'] is String &&
                  (a['rawPanelText'] as String).isNotEmpty),
        );
        final hours = a['weeklyHours'];
        if (hours != null) {
          require(hours is Map && hours.length == 7);
          for (var day = 1; day <= 7; day++) {
            require((hours as Map).containsKey('$day'));
            final intervals = hours['$day'];
            require(intervals == null || intervals is List);
            if (intervals is List) {
              var previousEnd = 0;
              for (final interval in intervals) {
                require(interval is Map);
                final start = interval['startMinute'];
                final end = interval['endMinute'];
                require(start is int && end is int);
                require(
                  start >= previousEnd &&
                      start >= 0 &&
                      start < end &&
                      end <= 1440,
                );
                previousEnd = end as int;
              }
            }
          }
        }
        assertions++;
      }
    }
    require(
      data['stationCount'] == stations.length &&
          data['assertionCount'] == assertions,
    );
    require(
      data['review'] is Map &&
          data['review']['currentActivationVerified'] == false &&
          data['review']['coordinateMatches'] == located,
    );
    require(
      data['coordinateSources'] is List &&
          (data['coordinateSources'] as List).isNotEmpty,
    );
    for (final coordinateSource in data['coordinateSources'] as List) {
      require(
        coordinateSource is Map &&
            _https(coordinateSource['sourceUrl']) &&
            _date(coordinateSource['retrievedOn']) != null &&
            coordinateSource['coordinateSystem'] == 'WGS84 (EPSG:4326)' &&
            coordinateSource['sha256'] is String &&
            RegExp(r'^[a-f0-9]{64}$')
                .hasMatch(coordinateSource['sha256'] as String),
      );
    }
    return OfficialCoolingDirectory._(data);
  }

  static String periodLabel(Map<String, dynamic> assertion, DateTime now) {
    final start = _date(assertion['activationStart']);
    final end = _date(assertion['activationEnd']);
    if (start == null || end == null) return 'Activation dates not supplied';
    final utc = now.toUtc();
    final day = DateTime.utc(utc.year, utc.month, utc.day);
    if (end.isBefore(day.subtract(const Duration(days: 1)))) {
      return 'Expired activation listing';
    }
    if (start.isAfter(day.add(const Duration(days: 1)))) {
      return 'Future listed period · opening unverified';
    }
    return 'Listed period · opening unverified';
  }

  static bool _https(Object? value) {
    if (value is! String) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  static DateTime? _date(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final date = DateTime.tryParse('${value}T00:00:00Z');
    return date != null && date.toIso8601String().startsWith(value)
        ? date
        : null;
  }

  static bool _period(Object? start, Object? end) {
    if (start == null || end == null) return start == null && end == null;
    final a = _date(start);
    final b = _date(end);
    return a != null && b != null && !b.isBefore(a);
  }
}
