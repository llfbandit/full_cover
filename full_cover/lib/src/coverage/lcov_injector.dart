import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'lcov_record.dart';

class LcovInjector {
  /// Scans [packagePath]/lib/**/*.dart and injects zero-coverage records
  /// for any source files not already represented in [records].
  Future<List<LcovRecord>> inject(
    List<LcovRecord> records,
    String packagePath,
  ) async {
    final absPackagePath = p.normalize(p.absolute(packagePath));

    // Build a set of normalized absolute paths already in the records
    final existingFiles = {
      for (final r in records)
        p.normalize(
          p.isAbsolute(r.sourceFile)
              ? r.sourceFile
              : p.join(absPackagePath, r.sourceFile),
        ),
    };

    final injected = <LcovRecord>[];
    final glob = Glob('lib/**/*.dart');

    await for (final entity in glob.list(root: absPackagePath)) {
      if (entity is! File) continue;
      final file = entity as File;
      final absPath = p.normalize(file.absolute.path);
      if (existingFiles.contains(absPath)) continue;

      final lineCount = _countLines(file);
      injected.add(
        LcovRecord(
          sourceFile: absPath,
          lines: List.generate(lineCount, (i) => LineData(i + 1, 0)),
        ),
      );
    }

    return [...records, ...injected];
  }

  int _countLines(File file) {
    try {
      return file.readAsLinesSync().length;
    } catch (_) {
      return 0;
    }
  }
}
