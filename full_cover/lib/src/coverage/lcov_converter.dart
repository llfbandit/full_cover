import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:path/path.dart' as p;

import 'local_packages.dart';

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
  ///
  /// Packages outside the current project/workspace (e.g. pub-cache
  /// dependencies swept in by `--coverage-package=.*`) are not filtered here
  /// — that happens after parsing, in [LcovFilter.filterSiblingExcludes],
  /// so it applies uniformly to both `dart test` (JSON, converted here) and
  /// `flutter test` (which writes `lcov.info` directly, bypassing this class).
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
    final configPath = findPackageConfigPath(reportRoot);
    final resolver = await Resolver.create(
      packagesPath: configPath,
      sdkRoot: _sdkRoot(),
    );
    final reportOn = [
      p.join(reportRoot, 'lib'),
      if (crossPackageCoverage) ..._localLibDirs(configPath, reportRoot),
    ];
    final lcovContent = hitmap.formatLcov(resolver, reportOn: reportOn);
    File(lcovOutputPath).writeAsStringSync(lcovContent);
  }

  /// Returns the `lib/` directories of local packages listed in [configPath],
  /// excluding [reportRoot] itself (already in `reportOn`).
  List<String> _localLibDirs(String configPath, String reportRoot) {
    final absReportRoot = p.normalize(p.absolute(reportRoot));
    return localWorkspacePackages(configPath)
        .where((pkg) => pkg.rootPath != absReportRoot)
        .map((pkg) => pkg.libPath)
        .where((libPath) => Directory(libPath).existsSync())
        .toList();
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

  String? _sdkRoot() {
    try {
      // dart executable is at <sdk>/bin/dart
      return p.dirname(p.dirname(Platform.resolvedExecutable));
    } catch (_) {
      return null;
    }
  }
}
