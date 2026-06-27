import 'package:full_cover/src/config/config.dart';
import 'package:test/test.dart';

FullCoverConfig _parse(String yaml) =>
    FullCoverConfig.fromYaml(yaml, workspaceRoot: '/workspace');

void main() {
  group('FullCoverConfig.fromYaml', () {
    test('defaults when yaml is empty map', () {
      final config = _parse('{}');
      expect(config.globalLcov, isTrue);
      expect(config.outputDirectory, 'coverage');
      expect(config.htmlGlobal, isFalse);
      expect(config.htmlPackage, isFalse);
      expect(config.htmlDirectory, 'html');
      expect(config.packageExcludes, isEmpty);
      expect(config.globalFileExcludes, isEmpty);
    });

    test('parses output section', () {
      final config = _parse('''
output:
  global: false
  directory: out
  html:
    global: true
    package: true
    directory: report
''');
      expect(config.globalLcov, isFalse);
      expect(config.outputDirectory, 'out');
      expect(config.htmlGlobal, isTrue);
      expect(config.htmlPackage, isTrue);
      expect(config.htmlDirectory, 'report');
    });

    test('parses global_excludes', () {
      final config = _parse('''
global_excludes:
  files:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
''');
      expect(config.globalFileExcludes, ['**/*.g.dart', '**/*.freezed.dart']);
    });

    test('parses package_excludes', () {
      final config = _parse('''
package_excludes:
  - package: "packages/my_pkg"
    excludes:
      - "lib/src/gen/**"
''');
      expect(config.packageExcludes, hasLength(1));
      expect(config.packageExcludes.first.package, 'packages/my_pkg');
      expect(config.packageExcludes.first.excludes, ['lib/src/gen/**']);
    });

    test('parses limits section', () {
      final config = _parse('''
limits:
  line:
    minimum: 50
    average: 80
  branch:
    minimum: 40
  function:
    average: 70
''');
      expect(config.limits.line.minimum, 50);
      expect(config.limits.line.average, 80);
      expect(config.limits.branch.minimum, 40);
      expect(config.limits.branch.average, isNull);
      expect(config.limits.function.average, 70);
      expect(config.limits.function.minimum, isNull);
    });

    test('limits fall back to defaults when absent', () {
      final config = _parse('{}');
      expect(config.limits.line.effectiveMinimum, 30);
      expect(config.limits.line.effectiveAverage, 60);
    });
  });
}
