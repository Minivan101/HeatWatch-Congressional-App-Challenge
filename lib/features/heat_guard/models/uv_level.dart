enum UvLevel {
  low('Low', 'Lower UV intensity. Sun protection still matters outdoors.'),
  moderate('Moderate', 'Use sun protection and seek shade around midday.'),
  high('High', 'Strong UV. Favor shade and cover exposed skin.'),
  veryHigh(
    'Very high',
    'Very strong UV. Limit midday exposure and use sun protection.',
  ),
  extreme(
    'Extreme',
    'Intense UV. Reduce direct sun exposure, especially around midday.',
  );

  const UvLevel(this.label, this.description);
  final String label, description;
  static UvLevel? fromValue(double? value) {
    if (value == null || !value.isFinite || value < 0) return null;
    if (value < 3) return low;
    if (value < 6) return moderate;
    if (value < 8) return high;
    if (value < 11) return veryHigh;
    return extreme;
  }
}
