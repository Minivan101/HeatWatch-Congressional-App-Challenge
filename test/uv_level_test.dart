import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/heat_guard/models/uv_level.dart';

void main() {
  test('UV forecast decimals use the standard category boundaries', () {
    final examples = <double, UvLevel>{
      0: UvLevel.low,
      2.99: UvLevel.low,
      3: UvLevel.moderate,
      5.99: UvLevel.moderate,
      6: UvLevel.high,
      7.99: UvLevel.high,
      8: UvLevel.veryHigh,
      10.99: UvLevel.veryHigh,
      11: UvLevel.extreme,
      15: UvLevel.extreme,
    };
    for (final example in examples.entries) {
      expect(UvLevel.fromValue(example.key), example.value);
    }
  });
  test('missing or invalid UV never becomes low', () {
    for (final value in [null, -1.0, double.nan, double.infinity]) {
      expect(UvLevel.fromValue(value), isNull);
    }
  });
}
