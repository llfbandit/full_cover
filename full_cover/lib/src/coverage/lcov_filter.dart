import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'lcov_record.dart';

class LcovFilter {
  List<LcovRecord> apply({
    required List<LcovRecord> records,
    required List<String> filePatterns,
    String? packagePath,
  }) {
    if (filePatterns.isEmpty) return records;

    final globs = filePatterns.map(Glob.new).toList();

    return records.where((record) {
      final sf = record.sourceFile;
      for (final glob in globs) {
        if (_matches(glob, sf, packagePath)) return false;
      }
      return true;
    }).toList();
  }

  bool _matches(Glob glob, String filePath, String? packagePath) {
    if (glob.matches(filePath)) return true;

    if (packagePath != null) {
      final absBase = p.normalize(p.absolute(packagePath));
      final absFile = p.normalize(
        p.isAbsolute(filePath) ? filePath : p.absolute(filePath),
      );
      if (absFile.startsWith(absBase)) {
        final rel = p.relative(absFile, from: absBase);
        if (glob.matches(rel)) return true;
      }
    }

    return false;
  }
}
