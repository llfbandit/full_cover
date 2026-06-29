import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'lcov_filter.dart';
import 'lcov_record.dart';

class LcovInjector {
  /// Scans [packagePath]/lib/**/*.dart and injects zero-coverage records
  /// for any source files not already represented in [records].
  ///
  /// [filePatterns] are the same glob patterns used by [LcovFilter]: files
  /// matching any pattern are skipped during the scan, avoiding unnecessary
  /// file reads for files that would be filtered out anyway. Negation patterns
  /// (prefixed with `!`) are also honoured.
  Future<List<LcovRecord>> inject(
    List<LcovRecord> records,
    String packagePath, {
    List<String> filePatterns = const [],
  }) async {
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

    final parsed = LcovFilter.parsePatterns(filePatterns);
    final injected = <LcovRecord>[];
    final scanGlob = Glob('lib/**/*.dart');

    await for (final entity in scanGlob.list(root: absPackagePath)) {
      if (entity is! File) continue;
      final absPath = p.normalize(entity.absolute.path);
      if (existingFiles.contains(absPath)) continue;
      if (LcovFilter.isExcluded(absPath, parsed, absPackagePath)) continue;

      final lineCount = _countLines(entity as File);
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
