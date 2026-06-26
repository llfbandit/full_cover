import 'package:flutter_test/flutter_test.dart';
import 'package:ui_widgets/ui_widgets.dart';

void main() {
  group('ThresholdChecker', () {
    test('passes when both thresholds are met', () {
      final checker = ThresholdChecker(lines: 85.0, branches: 65.0);
      expect(checker.passes, isTrue);
      expect(checker.summary, 'Coverage thresholds met.');
    });

    test('fails when only line coverage is below threshold', () {
      final checker = ThresholdChecker(lines: 70.0, branches: 65.0);
      expect(checker.passes, isFalse);
      expect(checker.summary, 'Line coverage is below threshold.');
    });

    // The following branches in summary are intentionally not tested to
    // illustrate uncovered branches in the report:
    //   - lines < 80 && branches < 60  →  'Both … below threshold.'
    //   - lines >= 80 && branches < 60 →  'Branch coverage is below threshold.'
  });
}
