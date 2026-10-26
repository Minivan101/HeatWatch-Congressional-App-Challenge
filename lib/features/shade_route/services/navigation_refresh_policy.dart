class NavigationRefreshPolicy {
  const NavigationRefreshPolicy();
  bool isFresh(DateTime? at, DateTime now) =>
      at != null &&
      now.difference(at) <= const Duration(seconds: 15) &&
      now.difference(at) >= const Duration(seconds: -5);
  bool shouldRefreshAfterGap({
    required DateTime now,
    required DateTime? lastComparison,
    required DateTime? previousFix,
    required DateTime fixAt,
  }) =>
      previousFix != null &&
      fixAt.difference(previousFix) >= const Duration(minutes: 1) &&
      lastComparison != null &&
      now.difference(lastComparison) >= const Duration(seconds: 30);
  bool shouldRefresh({
    required DateTime now,
    required DateTime? lastComparison,
    required DateTime? fixAt,
    required bool busy,
    required double offRouteMeters,
  }) =>
      !busy &&
      lastComparison != null &&
      isFresh(fixAt, now) &&
      now.difference(lastComparison) >= const Duration(minutes: 5) &&
      offRouteMeters.isFinite &&
      offRouteMeters <= 35;
}
