import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'lcov_record.dart';

/// A sibling package's normalised absolute root path, paired with its
/// pre-parsed exclude patterns (its own `excludes` plus the shared
/// `globalExcludes`). Built once by [LcovFilter.prepareSiblingPatterns].
typedef SiblingPattern = ({
  String path,
  List<({Glob glob, bool negate})> patterns,
});

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
  /// Patterns are evaluated in order; the last match wins, and a `!` prefix
  /// negates (re-includes).
  static bool isExcluded(
    String filePath,
    List<({Glob glob, bool negate})> patterns,
    String? packagePath,
  ) {
    // Resolved once here rather than per pattern below — same for every pattern.
    final relativePath = packagePath == null
        ? null
        : _relativeTo(filePath, packagePath);

    var excluded = false;
    for (final p in patterns) {
      if (_matchesPath(p.glob, filePath, relativePath)) {
        excluded = !p.negate;
      }
    }
    return excluded;
  }

  /// Returns [filePath] relative to [packagePath], or null when it doesn't
  /// live under it.
  static String? _relativeTo(String filePath, String packagePath) {
    final absBase = p.normalize(p.absolute(packagePath));
    final absFile = p.normalize(
      p.isAbsolute(filePath) ? filePath : p.absolute(filePath),
    );
    if (!absFile.startsWith(absBase)) return null;
    return p.relative(absFile, from: absBase);
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

  /// Precomputes [siblings]' exclude patterns once, for reuse across every
  /// package's call to [filterSiblingExcludes] within a single run.
  static List<SiblingPattern> prepareSiblingPatterns({
    required Iterable<({String path, List<String> excludes})> siblings,
    required List<String> globalExcludes,
  }) {
    return [
      for (final s in siblings)
        (
          path: p.normalize(p.absolute(s.path)),
          patterns: _parsePatterns([...globalExcludes, ...s.excludes]),
        ),
    ];
  }

  /// Drops records for packages outside the current project/workspace, and
  /// records excluded by their own owning sibling's excludes or the shared
  /// [globalExcludes] (both folded into [siblingPatterns] already).
  ///
  /// Records under [currentPkgPath] pass through unchanged — the caller's
  /// regular [apply] step handles those.
  static List<LcovRecord> filterSiblingExcludes({
    required List<LcovRecord> records,
    required String currentPkgPath,
    required List<SiblingPattern> siblingPatterns,
  }) {
    final absCurrent = p.normalize(p.absolute(currentPkgPath));

    // `path + separator` avoids false prefix matches, e.g. `pkg` vs `pkg_b/`.
    final normalizedSiblings = siblingPatterns
        .where((s) => s.path != absCurrent)
        .toList();

    return records.where((r) {
      final absFile = p.normalize(
        p.isAbsolute(r.sourceFile) ? r.sourceFile : p.absolute(r.sourceFile),
      );

      // Most specific (longest-path) sibling that owns this file.
      SiblingPattern? owner;
      for (final sibling in normalizedSiblings) {
        if (!absFile.startsWith(sibling.path + p.separator)) continue;
        if (owner == null || sibling.path.length > owner.path.length) {
          owner = sibling;
        }
      }

      // Unowned: keep only if it's the current package's own file.
      if (owner == null) {
        return absFile == absCurrent ||
            absFile.startsWith(absCurrent + p.separator);
      }

      if (owner.patterns.isEmpty) return true;
      return !isExcluded(absFile, owner.patterns, owner.path);
    }).toList();
  }

  static bool _matchesPath(Glob glob, String filePath, String? relativePath) {
    if (glob.matches(filePath)) return true;
    if (relativePath != null && glob.matches(relativePath)) return true;
    return false;
  }
}
