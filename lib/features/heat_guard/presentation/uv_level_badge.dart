import 'package:flutter/material.dart';

import '../models/uv_level.dart';

(Color, Color) uvColors(UvLevel? level) => switch (level) {
  UvLevel.low => (const Color(0xFF1B5E20), const Color(0xFFE8F5E9)),
  UvLevel.moderate => (const Color(0xFF614900), const Color(0xFFFFF4B8)),
  UvLevel.high => (const Color(0xFF8A3500), const Color(0xFFFFE0B2)),
  UvLevel.veryHigh => (const Color(0xFF9C1515), const Color(0xFFFFDADA)),
  UvLevel.extreme => (const Color(0xFF6A1B9A), const Color(0xFFF1E1FC)),
  null => (const Color(0xFF424242), const Color(0xFFEEEEEE)),
};

class UvLevelBadge extends StatelessWidget {
  const UvLevelBadge({
    super.key,
    this.value,
    this.level,
    this.showValue = true,
  });
  final double? value;
  final UvLevel? level;
  final bool showValue;
  @override
  Widget build(BuildContext context) {
    final category = level ?? UvLevel.fromValue(value);
    final (ink, background) = uvColors(category);
    final label = category == null
        ? 'UV unavailable'
        : '${category.label}${showValue && value != null ? ' · UV ${value!.toStringAsFixed(1)}' : ''}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: ink.withValues(alpha: .25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: ink, fontWeight: FontWeight.w600),
      ),
    );
  }
}
