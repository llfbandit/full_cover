import 'dart:convert';
import 'dart:io';

import 'package:full_cover/src/coverage/lcov_converter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('fc_conv_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  const converter = LcovConverter();

  test('writes an empty lcov file when the coverage dir is empty', () async {
    final coverageDir = Directory(p.join(tempDir.path, 'coverage_json'))
      ..createSync();
    final lcovOut = p.join(tempDir.path, 'coverage', 'lcov.info');

    await converter.convert(
      coverageJsonDir: coverageDir.path,
      lcovOutputPath: lcovOut,
      reportRoot: tempDir.path,
    );

    final out = File(lcovOut);
    expect(out.existsSync(), isTrue);
    expect(out.readAsStringSync(), isEmpty);
  });

  test('writes an empty lcov file when the coverage dir is missing', () async {
    final lcovOut = p.join(tempDir.path, 'coverage', 'lcov.info');

    await converter.convert(
      coverageJsonDir: p.join(tempDir.path, 'does_not_exist'),
      lcovOutputPath: lcovOut,
      reportRoot: tempDir.path,
    );

    expect(File(lcovOut).readAsStringSync(), isEmpty);
  });

  test('ignores non-json files in the coverage dir', () async {
    final coverageDir = Directory(p.join(tempDir.path, 'coverage_json'))
      ..createSync();
    File(p.join(coverageDir.path, 'notes.txt')).writeAsStringSync('ignore me');
    final lcovOut = p.join(tempDir.path, 'coverage', 'lcov.info');

    await converter.convert(
      coverageJsonDir: coverageDir.path,
      lcovOutputPath: lcovOut,
      reportRoot: tempDir.path,
    );

    expect(File(lcovOut).readAsStringSync(), isEmpty);
  });

  test('creates the output parent directory if absent', () async {
    final coverageDir = Directory(p.join(tempDir.path, 'coverage_json'))
      ..createSync();
    final lcovOut = p.join(tempDir.path, 'nested', 'deeper', 'lcov.info');

    await converter.convert(
      coverageJsonDir: coverageDir.path,
      lcovOutputPath: lcovOut,
      reportRoot: tempDir.path,
    );

    expect(
      Directory(p.join(tempDir.path, 'nested', 'deeper')).existsSync(),
      isTrue,
    );
    expect(File(lcovOut).existsSync(), isTrue);
  });

  // Two-package workspace under [root]; returns a JSON coverage dir (under
  // pkg_a) with hits for both, simulating pkg_a's tests hitting pkg_b code.
  ({Directory pkgADir, Directory jsonDir}) buildWorkspace(Directory root) {
    final pkgADir = Directory(p.join(root.path, 'pkg_a'))..createSync();
    Directory(p.join(pkgADir.path, 'lib')).createSync();
    File(
      p.join(pkgADir.path, 'lib', 'a.dart'),
    ).writeAsStringSync('int a = 1;\n');

    final pkgBDir = Directory(p.join(root.path, 'pkg_b'))..createSync();
    Directory(p.join(pkgBDir.path, 'lib')).createSync();
    File(
      p.join(pkgBDir.path, 'lib', 'b.dart'),
    ).writeAsStringSync('int b = 2;\n');

    Directory(p.join(root.path, '.dart_tool')).createSync();
    File(
      p.join(root.path, '.dart_tool', 'package_config.json'),
    ).writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'pkg_a', 'rootUri': '../pkg_a/', 'packageUri': 'lib/'},
          {'name': 'pkg_b', 'rootUri': '../pkg_b/', 'packageUri': 'lib/'},
          // Absolute URI → pub-cache package, must be ignored.
          {
            'name': 'collection',
            'rootUri': 'file:///pub-cache/collection-1.0/',
            'packageUri': 'lib/',
          },
        ],
      }),
    );

    final jsonDir = Directory(p.join(pkgADir.path, 'cov'))..createSync();
    File(p.join(jsonDir.path, 'cov.json')).writeAsStringSync(
      jsonEncode({
        'type': 'CodeCoverage',
        'coverage': [
          {
            'source': 'package:pkg_a/a.dart',
            'script': {
              'type': '@Script',
              'fixedId': true,
              'id': 's1',
              'uri': 'package:pkg_a/a.dart',
              '_kind': 'library',
            },
            'hits': [1, 5],
          },
          {
            'source': 'package:pkg_b/b.dart',
            'script': {
              'type': '@Script',
              'fixedId': true,
              'id': 's2',
              'uri': 'package:pkg_b/b.dart',
              '_kind': 'library',
            },
            'hits': [1, 3],
          },
        ],
      }),
    );

    return (pkgADir: pkgADir, jsonDir: jsonDir);
  }

  test(
    'includes sibling local package hits when crossPackageCoverage is true',
    () async {
      final (:pkgADir, :jsonDir) = buildWorkspace(tempDir);
      final lcovOut = p.join(pkgADir.path, 'coverage', 'lcov.info');

      await converter.convert(
        coverageJsonDir: jsonDir.path,
        lcovOutputPath: lcovOut,
        reportRoot: pkgADir.path,
        crossPackageCoverage: true,
      );

      final out = File(lcovOut).readAsStringSync();
      expect(out, contains('a.dart'), reason: 'own package hits present');
      expect(out, contains('b.dart'), reason: 'sibling package hits included');
    },
  );

  test(
    'excludes sibling local package hits when crossPackageCoverage is false',
    () async {
      final (:pkgADir, :jsonDir) = buildWorkspace(tempDir);
      final lcovOut = p.join(pkgADir.path, 'coverage', 'lcov.info');

      await converter.convert(
        coverageJsonDir: jsonDir.path,
        lcovOutputPath: lcovOut,
        reportRoot: pkgADir.path,
        crossPackageCoverage: false,
      );

      final out = File(lcovOut).readAsStringSync();
      expect(out, contains('a.dart'), reason: 'own package hits present');
      expect(
        out,
        isNot(contains('b.dart')),
        reason: 'sibling package hits excluded',
      );
    },
  );

  test('converts VM coverage json to lcov', () async {
    // A real lib file resolvable via a minimal package_config.
    Directory(p.join(tempDir.path, 'lib')).createSync();
    File(
      p.join(tempDir.path, 'lib', 'foo.dart'),
    ).writeAsStringSync('int a = 1;\nint b = 2;\n');
    Directory(p.join(tempDir.path, '.dart_tool')).createSync();
    File(
      p.join(tempDir.path, '.dart_tool', 'package_config.json'),
    ).writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'pkg', 'rootUri': '../', 'packageUri': 'lib/'},
        ],
      }),
    );

    // Hand-written VM coverage: line 1 hit 3 times, line 2 never.
    final jsonDir = Directory(p.join(tempDir.path, 'cov'))..createSync();
    File(p.join(jsonDir.path, 'cov.json')).writeAsStringSync(
      jsonEncode({
        'type': 'CodeCoverage',
        'coverage': [
          {
            'source': 'package:pkg/foo.dart',
            'script': {
              'type': '@Script',
              'fixedId': true,
              'id': 's',
              'uri': 'package:pkg/foo.dart',
              '_kind': 'library',
            },
            'hits': [1, 3, 2, 0],
          },
        ],
      }),
    );

    final lcovOut = p.join(tempDir.path, 'coverage', 'lcov.info');
    await converter.convert(
      coverageJsonDir: jsonDir.path,
      lcovOutputPath: lcovOut,
      reportRoot: tempDir.path,
    );

    final out = File(lcovOut).readAsStringSync();
    expect(out, contains('foo.dart'));
    expect(out, contains('DA:1,3'));
    expect(out, contains('DA:2,0'));
  });
}
