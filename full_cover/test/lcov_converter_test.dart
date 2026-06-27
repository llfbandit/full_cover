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
