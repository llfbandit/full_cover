import 'dart:io';

import 'package:full_cover/src/config/config.dart';
import 'package:full_cover/src/full_cover_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('fc_runner_'));
  tearDown(() => root.deleteSync(recursive: true));

  void makePkg(String rel) {
    final dir = p.join(root.path, rel);
    Directory(p.join(dir, 'lib')).createSync(recursive: true);
    File(p.join(dir, 'lib', 'main.dart')).writeAsStringSync('int x = 1;\n');
    File(
      p.join(dir, 'pubspec.yaml'),
    ).writeAsStringSync('name: ${rel.replaceAll('/', '_')}\n');
  }

  String lcovRecord(String file) =>
      '''
SF:$file
DA:1,1
LF:1
LH:1
end_of_record
''';

  test(
    'drops cross-package hits landing in a fully excluded (excludes: **) '
    'sibling instead of mistaking them for the root package\'s own files',
    () async {
      Directory(p.join(root.path, 'lib')).createSync(recursive: true);
      File(
        p.join(root.path, 'lib', 'app.dart'),
      ).writeAsStringSync('int a = 1;\n');
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: app
workspace:
  - packages/testing/mocks
  - packages/translations
''');

      makePkg('packages/testing/mocks');
      makePkg('packages/translations');

      // Simulates cross-package coverage hitting fully-excluded packages.
      Directory(p.join(root.path, 'coverage')).createSync(recursive: true);
      File(p.join(root.path, 'coverage', 'lcov.info')).writeAsStringSync(
        lcovRecord(p.join(root.path, 'lib', 'app.dart')) +
            lcovRecord(
              p.join(
                root.path,
                'packages',
                'testing',
                'mocks',
                'lib',
                'main.dart',
              ),
            ) +
            lcovRecord(
              p.join(root.path, 'packages', 'translations', 'lib', 'main.dart'),
            ),
      );

      final config = FullCoverConfig.fromYaml('''
package_excludes:
  - package: "packages/testing/**"
  - package: "packages/translations"
cross_package_coverage: true
''', workspaceRoot: root.path);

      await FullCoverRunner(skipTests: true).run(config);

      final merged = File(
        p.join(root.path, 'coverage', 'lcov.info'),
      ).readAsStringSync();
      expect(merged, contains('app.dart'));
      expect(merged, isNot(contains('testing')));
      expect(merged, isNot(contains('translations')));
    },
  );
}
