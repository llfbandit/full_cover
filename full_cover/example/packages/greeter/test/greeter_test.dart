import 'package:greeter/greeter.dart';
import 'package:test/test.dart';

void main() {
  group('Messages', () {
    test('hello returns greeting', () {
      expect(Messages.hello('World'), 'Hello, World!');
      expect(Messages.hello('Dart'), 'Hello, Dart!');
    });

    // goodbye() and welcome() are intentionally not tested:
    // - they show up as uncovered lines in messages.dart

    // UndocumentedFeature is intentionally not tested, but it is also
    // excluded via per-package excludes so it won't appear in the report.
  });
}
