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
          // A posix context is required regardless of platform: package:glob's
          // default (platform) context can't match a leading `**` across a
          // Windows drive-letter root (e.g. `**/foo/**` never matches
          // `D:\a\foo\b.dart`, only `a\foo\b.dart`) — see [_matchesPath].
          glob: Glob(
            raw.startsWith('!') ? raw.substring(1) : raw,
            context: p.posix,
          ),
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

    return records.where((r) {
      final absFile = p.normalize(
        p.isAbsolute(r.sourceFile) ? r.sourceFile : p.absolute(r.sourceFile),
      );

      // Most specific (longest-path) owner among every sibling AND the
      // current package itself — the current package must stay in this
      // competition, or a shorter ancestor (e.g. the workspace root, which
      // is a path-prefix of every nested package) wins by elimination and
      // wrongly claims the current package's own files.
      final ownsSelf =
          absFile == absCurrent || absFile.startsWith(absCurrent + p.separator);
      SiblingPattern? owner;
      var ownerPathLength = ownsSelf ? absCurrent.length : -1;
      for (final sibling in siblingPatterns) {
        // current handled via ownsSelf
        if (sibling.path == absCurrent) {
          continue;
        }
        if (!absFile.startsWith(sibling.path + p.separator)) continue;
        if (sibling.path.length > ownerPathLength) {
          owner = sibling;
          ownerPathLength = sibling.path.length;
        }
      }

      // The current package is the most specific match (or the only match):
      // pass through unchanged — the caller's own [apply] step handles it.
      if (owner == null) return ownsSelf;

      if (owner.patterns.isEmpty) return true;
      return !isExcluded(absFile, owner.patterns, owner.path);
    }).toList();
  }

  static bool _matchesPath(Glob glob, String filePath, String? relativePath) {
    if (glob.matches(_toPosix(filePath))) return true;
    if (relativePath != null && glob.matches(_toPosix(relativePath))) {
      return true;
    }
    return false;
  }

  static String _toPosix(String path) => path.replaceAll(r'\', '/');
}
