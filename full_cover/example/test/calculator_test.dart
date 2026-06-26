import 'package:full_cover_example/calculator.dart';
import 'package:test/test.dart';

void main() {
  group('Calculator', () {
    final calc = Calculator();

    test('add returns sum', () {
      expect(calc.add(2, 3), 5);
      expect(calc.add(-1, 1), 0);
    });

    test('subtract returns difference', () {
      expect(calc.subtract(10, 4), 6);
    });

    test('divide returns quotient', () {
      expect(calc.divide(10, 2), 5.0);
      expect(calc.divide(7, 2), 3.5);
    });

    // multiply() is intentionally not tested — shows uncovered lines in operations.dart
  });
}
