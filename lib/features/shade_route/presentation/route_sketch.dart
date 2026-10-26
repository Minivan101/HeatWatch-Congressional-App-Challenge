import 'package:flutter/material.dart';

class RouteSketch extends StatelessWidget {
  const RouteSketch({
    required this.encodedRoutes,
    required this.selectedIndex,
    super.key,
  });

  final List<String> encodedRoutes;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final paths = encodedRoutes.map(decodeRoutePolyline).toList();
    return Semantics(
      label: 'Schematic route preview, Route ${selectedIndex + 1} selected',
      child: SizedBox(
        width: double.infinity,
        height: 160,
        child: CustomPaint(
          painter: _RouteSketchPainter(
            paths: paths,
            selectedIndex: selectedIndex,
            selectedColor: Theme.of(context).colorScheme.primary,
            otherColor: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

List<Offset> decodeRoutePolyline(String encoded) {
  if (encoded.isEmpty) throw const FormatException('Empty route geometry');
  var position = 0;
  var latitude = 0;
  var longitude = 0;
  final points = <Offset>[];

  int readDelta() {
    var value = 0;
    var shift = 0;
    while (true) {
      if (position >= encoded.length || shift > 30) {
        throw const FormatException('Invalid route geometry');
      }
      final next = encoded.codeUnitAt(position++) - 63;
      if (next < 0 || next > 63) {
        throw const FormatException('Invalid route geometry');
      }
      value |= (next & 0x1f) << shift;
      if (next < 0x20) break;
      shift += 5;
    }
    return value.isOdd ? -(value + 1) ~/ 2 : value ~/ 2;
  }

  while (position < encoded.length) {
    latitude += readDelta();
    longitude += readDelta();
    final lat = latitude / 1e5;
    final lng = longitude / 1e5;
    if (lat.abs() > 90 || lng.abs() > 180) {
      throw const FormatException('Route coordinates are invalid');
    }
    points.add(Offset(lng, lat));
  }
  if (points.length < 2) {
    throw const FormatException('Route needs two points');
  }
  return points;
}

class _RouteSketchPainter extends CustomPainter {
  const _RouteSketchPainter({
    required this.paths,
    required this.selectedIndex,
    required this.selectedColor,
    required this.otherColor,
  });

  final List<List<Offset>> paths;
  final int selectedIndex;
  final Color selectedColor;
  final Color otherColor;

  @override
  void paint(Canvas canvas, Size size) {
    final allPoints = paths.expand((path) => path).toList();
    final minX = allPoints
        .map((point) => point.dx)
        .reduce((a, b) => a < b ? a : b);
    final maxX = allPoints
        .map((point) => point.dx)
        .reduce((a, b) => a > b ? a : b);
    final minY = allPoints
        .map((point) => point.dy)
        .reduce((a, b) => a < b ? a : b);
    final maxY = allPoints
        .map((point) => point.dy)
        .reduce((a, b) => a > b ? a : b);
    const inset = 20.0;
    final xRange = maxX - minX == 0 ? 1.0 : maxX - minX;
    final yRange = maxY - minY == 0 ? 1.0 : maxY - minY;
    Offset plot(Offset point) => Offset(
      inset + (point.dx - minX) / xRange * (size.width - 2 * inset),
      size.height -
          inset -
          (point.dy - minY) / yRange * (size.height - 2 * inset),
    );

    for (var index = 0; index < paths.length; index++) {
      if (index == selectedIndex) continue;
      _drawPath(canvas, paths[index], plot, otherColor, 2);
    }
    _drawPath(canvas, paths[selectedIndex], plot, selectedColor, 5);
    final start = plot(paths[selectedIndex].first);
    final end = plot(paths[selectedIndex].last);
    canvas.drawCircle(start, 6, Paint()..color = selectedColor);
    canvas.drawCircle(end, 6, Paint()..color = selectedColor);
    canvas.drawCircle(start, 3, Paint()..color = Colors.white);
    canvas.drawCircle(end, 3, Paint()..color = Colors.white);
  }

  void _drawPath(
    Canvas canvas,
    List<Offset> points,
    Offset Function(Offset) plot,
    Color color,
    double width,
  ) {
    final path = Path()..moveTo(plot(points.first).dx, plot(points.first).dy);
    for (final point in points.skip(1)) {
      final position = plot(point);
      path.lineTo(position.dx, position.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _RouteSketchPainter oldDelegate) =>
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.selectedColor != selectedColor ||
      oldDelegate.otherColor != otherColor ||
      oldDelegate.paths != paths;
}
