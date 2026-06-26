// Intentionally untested — demonstrates zero-coverage injection.
// full_cover will add this file to the report with 0% coverage even though
// dart test never loaded it.
class Uncovered {
  String uncovered(num value) => 'Uncovered: $value';

  String uncoveredError(String message) => 'Uncovered: $message';

  String uncoveredPercent(double ratio) {
    return '${(ratio * 100).toStringAsFixed(1)}%';
  }
}
