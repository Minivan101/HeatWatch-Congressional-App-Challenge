import 'package:flutter_test/flutter_test.dart';
import 'package:heatwatch/features/shade_route/presentation/route_sketch.dart';

void main() {
  test('route sketch decodes the same standard polyline format as backend', () {
    final points = decodeRoutePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(points, [
      const Offset(-120.2, 38.5),
      const Offset(-120.95, 40.7),
      const Offset(-126.453, 43.252),
    ]);
    expect(() => decodeRoutePolyline('bad'), throwsFormatException);
  });
}
