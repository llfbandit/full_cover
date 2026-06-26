import 'package:flutter/material.dart';

/// A small coloured badge that displays a coverage percentage.
///
/// Colour reflects the coverage level:
///   ≥ 80 % → green   (high)
///   ≥ 60 % → amber   (medium)
///   < 60 % → red     (low)
class CoverageBadge extends StatelessWidget {
  final double percentage;

  const CoverageBadge({super.key, required this.percentage});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _badgeColor(),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${percentage.toStringAsFixed(1)}%',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _badgeColor() {
    if (percentage >= 80) return const Color(0xFF2e7d32);
    if (percentage >= 60) return const Color(0xFFd97706);
    return const Color(0xFFb91c1c);
  }
}
