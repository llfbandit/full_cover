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

    final parsed = _parsePatterns(filePatterns);

    return records
        .where((r) => !isExcluded(r.sourceFile, parsed, packagePath))
        .toList();
  }

  /// Returns true when [filePath] should be excluded given [patterns].
  ///
  /// Patterns are evaluated in order; the last matching pattern wins.
  /// A pattern prefixed with `!` negates (re-includes) a prior exclusion.
  static bool isExcluded(
    String filePath,
    List<({Glob glob, bool negate})> patterns,
    String? packagePath,
  ) {
    var excluded = false;
    for (final p in patterns) {
      if (_matchesPath(p.glob, filePath, packagePath)) {
        excluded = !p.negate;
      }
    }
    return excluded;
  }

  /// Parses raw pattern strings into (glob, negate) pairs.
  static List<({Glob glob, bool negate})> parsePatterns(
    List<String> filePatterns,
  ) => _parsePatterns(filePatterns);

  static List<({Glob glob, bool negate})> _parsePatterns(
    List<String> filePatterns,
  ) {
    return [
      for (final raw in filePatterns)
        (
          glob: Glob(raw.startsWith('!') ? raw.substring(1) : raw),
          negate: raw.startsWith('!'),
        ),
    ];
  }

  /// Removes records that belong to a sibling local package and are excluded
  /// by that package's own [excludes] or the shared [globalExcludes].
  ///
  /// Records that belong to [currentPkgPath] are passed through unchanged —
  /// they are handled by the caller's regular [apply] step.
  /// Records that don't belong to any known sibling are also kept.
  static List<LcovRecord> filterSiblingExcludes({
    required List<LcovRecord> records,
    required String currentPkgPath,
    required Iterable<({String path, List<String> excludes})> siblings,
    required List<String> globalExcludes,
  }) {
    final absCurrent = p.normalize(p.absolute(currentPkgPath));
    return records.where((r) {
      final absFile = p.normalize(
        p.isAbsolute(r.sourceFile) ? r.sourceFile : p.absolute(r.sourceFile),
      );
      if (absFile.startsWith(absCurrent)) return true;
      for (final sibling in siblings) {
        final absSibling = p.normalize(p.absolute(sibling.path));
        if (absFile.startsWith(absSibling)) {
          final patterns = [...globalExcludes, ...sibling.excludes];
          if (patterns.isEmpty) return true;
          final parsed = _parsePatterns(patterns);
          return !isExcluded(absFile, parsed, absSibling);
        }
      }
      return true;
    }).toList();
  }

  static bool _matchesPath(Glob glob, String filePath, String? packagePath) {
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
