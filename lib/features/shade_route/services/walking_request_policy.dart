DateTime? walkingRetryTime(String? value, DateTime now) {
  if (value == null) return null;
  final seconds = int.tryParse(value.trim());
  if (seconds != null && seconds >= 0 && seconds <= 86400 * 365) {
    return now.add(Duration(seconds: seconds));
  }
  final m = RegExp(
    r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  if (m == null) return null;
  final month =
      const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ].indexOf(m[2]!) +
      1;
  final day = int.parse(m[1]!),
      hour = int.parse(m[4]!),
      minute = int.parse(m[5]!),
      second = int.parse(m[6]!);
  if (month == 0 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final result = DateTime.utc(
    int.parse(m[3]!),
    month,
    day,
    hour,
    minute,
    second,
  );
  return result.month == month && result.day == day ? result : null;
}
