import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/shade_route/services/navigation_refresh_policy.dart';

void main() {
  test('brief stale intervals do not cause provider storms; a sustained GPS outage can refresh', () {
    const p = NavigationRefreshPolicy();
    final now = DateTime.utc(2026, 10, 11, 17);
    for (final seconds in [16, 30, 59]) {
      expect(
        p.shouldRefreshAfterGap(
          now: now,
          lastComparison: now.subtract(const Duration(minutes: 1)),
          previousFix: now.subtract(Duration(seconds: seconds)),
          fixAt: now,
        ),
        false,
      );
    }
    expect(
      p.shouldRefreshAfterGap(
        now: now,
        lastComparison: now.subtract(const Duration(minutes: 1)),
        previousFix: now.subtract(const Duration(seconds: 90)),
        fixAt: now,
      ),
      true,
    );
    expect(
      p.shouldRefreshAfterGap(
        now: now,
        lastComparison: now.subtract(const Duration(seconds: 10)),
        previousFix: now.subtract(const Duration(seconds: 90)),
        fixAt: now,
      ),
      false,
    );
  });
  test('refresh needs five minutes, fresh GPS, an on-route walk and no pending work', () {
    const policy = NavigationRefreshPolicy();
    final now = DateTime.utc(2026, 10, 11, 10);
    bool due({
      int minutes = 5,
      int age = 0,
      bool busy = false,
      double off = 0,
    }) => policy.shouldRefresh(
      now: now,
      lastComparison: now.subtract(Duration(minutes: minutes)),
      fixAt: now.subtract(Duration(seconds: age)),
      busy: busy,
      offRouteMeters: off,
    );
    expect(due(), true);
    expect(due(minutes: 4), false);
    expect(due(age: 16), false);
    expect(due(age: -6), false);
    expect(due(busy: true), false);
    expect(due(off: 36), false);
    expect(due(off: double.nan), false);
    expect(
      policy.shouldRefresh(
        now: now,
        lastComparison: null,
        fixAt: now,
        busy: false,
        offRouteMeters: 0,
      ),
      false,
    );
  });
}
