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

  /// Removes records that don't belong to the current project/workspace, and
  /// records that belong to a sibling local package but are excluded by that
  /// package's own [excludes] or the shared [globalExcludes].
  ///
  /// [siblings] is the full set of packages discovered in the workspace, so
  /// a record that belongs to neither [currentPkgPath] nor a known sibling
  /// is coverage for a package outside the current project (e.g. a pub-cache
  /// dependency swept in by `--coverage-package=.*`) and is dropped.
  ///
  /// Records that belong to [currentPkgPath] are passed through unchanged —
  /// they are handled by the caller's regular [apply] step.
  static List<LcovRecord> filterSiblingExcludes({
    required List<LcovRecord> records,
    required String currentPkgPath,
    required Iterable<({String path, List<String> excludes})> siblings,
    required List<String> globalExcludes,
  }) {
    final absCurrent = p.normalize(p.absolute(currentPkgPath));

    // Exclude the current package from the sibling list and pre-normalise paths.
    // Using `path + separator` avoids false prefix matches between packages
    // whose names share a common prefix (e.g. `pkg` matching `pkg_b/…`), and
    // also prevents the workspace-root package from treating sub-package files
    // as its own.
    final normalizedSiblings = [
      for (final s in siblings)
        (path: p.normalize(p.absolute(s.path)), excludes: s.excludes),
    ].where((s) => s.path != absCurrent).toList();

    // Pre-compute Glob objects per sibling so they are compiled once, not once
    // per record. Glob construction compiles a regex internally.
    final siblingPatterns = {
      for (final s in normalizedSiblings)
        s.path: _parsePatterns([...globalExcludes, ...s.excludes]),
    };

    return records.where((r) {
      final absFile = p.normalize(
        p.isAbsolute(r.sourceFile) ? r.sourceFile : p.absolute(r.sourceFile),
      );

      // Find the most specific (longest-path) sibling that owns this file.
      ({String path, List<String> excludes})? owner;
      for (final sibling in normalizedSiblings) {
        if (!absFile.startsWith(sibling.path + p.separator)) continue;
        if (owner == null || sibling.path.length > owner.path.length) {
          owner = sibling;
        }
      }

      // No sibling owns it: keep only if it's the current package's own
      // file. Anything else belongs to a package outside the workspace.
      if (owner == null) {
        return absFile == absCurrent ||
            absFile.startsWith(absCurrent + p.separator);
      }

      final patterns = siblingPatterns[owner.path]!;
      if (patterns.isEmpty) return true;
      return !isExcluded(absFile, patterns, owner.path);
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
