/// Checks whether coverage percentages meet the configured thresholds.
class ThresholdChecker {
  final double lines;
  final double branches;

  const ThresholdChecker({required this.lines, required this.branches});

  bool get passes => lines >= 80.0 && branches >= 60.0;

  /// Human-readable explanation of which threshold(s) are not met.
  String get summary {
    if (passes) return 'Coverage thresholds met.';
    if (lines < 80.0 && branches < 60.0) {
      return 'Both line and branch coverage are below threshold.';
    }
    if (lines < 80.0) return 'Line coverage is below threshold.';
    return 'Branch coverage is below threshold.';
  }
}
