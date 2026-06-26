import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_widgets/ui_widgets.dart';

void main() {
  group('CoverageBadge', () {
    testWidgets('displays the percentage text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CoverageBadge(percentage: 85.0)),
        ),
      );
      expect(find.text('85.0%'), findsOneWidget);
    });

    // Only the high-coverage colour branch (>= 80) is exercised above.
    // Medium (>= 60) and low (< 60) colour branches are not tested.
  });
}
