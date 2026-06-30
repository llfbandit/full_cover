import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:path/path.dart' as p;

/// Converts raw VM coverage JSON (as produced by `dart test --coverage`) into
/// LCOV format using the `package:coverage` API.
class LcovConverter {
  const LcovConverter();

  /// Converts every `*.json` file under [coverageJsonDir] into LCOV and writes
  /// the result to [lcovOutputPath].
  ///
  /// [reportRoot] is the package directory whose `lib/` is reported on; it is
  /// also the starting point for locating `package_config.json`. When no JSON
  /// coverage is found an empty LCOV file is written.
  Future<void> convert({
    required String coverageJsonDir,
    required String lcovOutputPath,
    required String reportRoot,
    bool crossPackageCoverage = true,
  }) async {
    final jsonFiles = _jsonFiles(Directory(coverageJsonDir));

    Directory(p.dirname(lcovOutputPath)).createSync(recursive: true);

    if (jsonFiles.isEmpty) {
      File(lcovOutputPath).writeAsStringSync('');
      return;
    }

    final hitmap = await HitMap.parseFiles(jsonFiles);
    final resolver = await Resolver.create(
      packagesPath: _packageConfigPath(reportRoot),
      sdkRoot: _sdkRoot(),
    );
    final configPath = _packageConfigPath(reportRoot);
    final reportOn = [
      p.join(reportRoot, 'lib'),
      if (crossPackageCoverage) ..._localLibDirs(configPath, reportRoot),
    ];
    final lcovContent = hitmap.formatLcov(resolver, reportOn: reportOn);
    File(lcovOutputPath).writeAsStringSync(lcovContent);
  }

  /// Returns the `lib/` directories of local (non-pub-cache) packages listed
  /// in [configPath], excluding [reportRoot] itself (already in `reportOn`).
  ///
  /// In a Dart workspace `package_config.json`, local packages use a relative
  /// `rootUri` (e.g. `"../other_pkg/"`). Pub-cache entries use an absolute
  /// `file:///…` URI — those are skipped.
  List<String> _localLibDirs(String configPath, String reportRoot) {
    final file = File(configPath);
    if (!file.existsSync()) return [];
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final packages =
          (json['packages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final configDir = p.dirname(configPath); // the .dart_tool/ directory
      final absReportRoot = p.normalize(p.absolute(reportRoot));
      final result = <String>[];
      for (final pkg in packages) {
        final rootUri = pkg['rootUri'] as String?;
        if (rootUri == null) continue;
        // Absolute URIs (file://, drive letters, /…) → pub cache or SDK; skip.
        if (Uri.parse(rootUri).isAbsolute) continue;
        final rootPath = p.normalize(p.join(configDir, rootUri));
        if (p.normalize(p.absolute(rootPath)) == absReportRoot) continue;
        final packageUri = pkg['packageUri'] as String? ?? 'lib/';
        final libPath = p.normalize(p.join(rootPath, packageUri));
        if (Directory(libPath).existsSync()) result.add(libPath);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  List<File> _jsonFiles(Directory dir) {
    try {
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
    } catch (_) {
      return <File>[];
    }
  }

  /// Returns the package_config.json path for [pkgPath].
  ///
  /// In a pub workspace the file lives at the workspace root, not inside each
  /// sub-package. Walk up the directory tree until we find one.
  String _packageConfigPath(String pkgPath) {
    var dir = Directory(pkgPath);
    while (true) {
      final candidate = p.join(dir.path, '.dart_tool', 'package_config.json');
      if (File(candidate).existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break; // filesystem root
      dir = parent;
    }
    // Fall back to expected location so the original error message is preserved.
    return p.join(pkgPath, '.dart_tool', 'package_config.json');
  }

  String? _sdkRoot() {
    try {
      // dart executable is at <sdk>/bin/dart
      return p.dirname(p.dirname(Platform.resolvedExecutable));
    } catch (_) {
      return null;
    }
  }
}
