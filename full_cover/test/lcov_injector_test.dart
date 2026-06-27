import 'dart:io';

import 'package:full_cover/src/coverage/lcov_injector.dart';
import 'package:full_cover/src/coverage/lcov_record.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fc_inj_');
    Directory(p.join(tempDir.path, 'lib', 'src')).createSync(recursive: true);
  });
  tearDown(() => tempDir.deleteSync(recursive: true));

  // All dart files go under lib/src/ so they match lib/**/*.dart
  File writeLib(String name, String content) {
    final f = File(p.join(tempDir.path, 'lib', 'src', name));
    f.writeAsStringSync(content);
    return f;
  }

  String abs(File f) => p.normalize(p.absolute(f.path));

  final injector = LcovInjector();

  test('injects zero-coverage record for untracked file', () async {
    writeLib('untested.dart', 'int x = 1;\nint y = 2;\n');

    final result = await injector.inject([], tempDir.path);
    expect(result, hasLength(1));
    expect(result.first.linesFound, 2);
    expect(result.first.linesHit, 0);
  });

  test('does not inject record for already-tracked file', () async {
    final file = writeLib('existing.dart', 'int a = 1;\n');
    final existing = LcovRecord(sourceFile: abs(file), lines: [LineData(1, 1)]);

    final result = await injector.inject([existing], tempDir.path);
    expect(result, hasLength(1));
    expect(result.first.linesHit, 1);
  });

  test('injects only missing files when some are tracked', () async {
    final tracked = writeLib('tracked.dart', 'int a = 1;\n');
    writeLib('missing.dart', 'int b = 2;\nint c = 3;\n');

    final existing = LcovRecord(
      sourceFile: abs(tracked),
      lines: [LineData(1, 5)],
    );
    final result = await injector.inject([existing], tempDir.path);
    expect(result, hasLength(2));

    final injected = result.firstWhere((r) => r.sourceFile != abs(tracked));
    expect(injected.linesFound, 2);
    expect(injected.linesHit, 0);
  });

  test('returns original records unchanged when no missing files', () async {
    final file = writeLib('only.dart', 'void fn() {}\n');
    final existing = LcovRecord(sourceFile: abs(file), lines: [LineData(1, 1)]);

    final result = await injector.inject([existing], tempDir.path);
    expect(result, hasLength(1));
    expect(result.first.linesHit, 1);
  });

  test('handles empty lib directory gracefully', () async {
    final result = await injector.inject([], tempDir.path);
    expect(result, isEmpty);
  });
}
