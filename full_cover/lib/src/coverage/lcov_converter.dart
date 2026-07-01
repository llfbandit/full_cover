import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:path/path.dart' as p;

import 'local_packages.dart';

/// Converts raw VM coverage JSON (as produced by `dart test --coverage`) into
/// LCOV format using the `package:coverage` API.
class LcovConverter {
  const LcovConverter();

  /// Converts every `*.json` file under [coverageJsonDir] into LCOV at
  /// [lcovOutputPath] (empty if none found). [reportRoot] is the package
  /// directory whose `lib/` is reported on and the default starting point
  /// for locating `package_config.json` — pass [packageConfigPath] and
  /// [localPackages] to reuse an already-resolved one instead.
  Future<void> convert({
    required String coverageJsonDir,
    required String lcovOutputPath,
    required String reportRoot,
    bool crossPackageCoverage = true,
    String? packageConfigPath,
    List<LocalPackage>? localPackages,
  }) async {
    final jsonFiles = _jsonFiles(Directory(coverageJsonDir));

    Directory(p.dirname(lcovOutputPath)).createSync(recursive: true);

    if (jsonFiles.isEmpty) {
      File(lcovOutputPath).writeAsStringSync('');
      return;
    }

    final hitmap = await HitMap.parseFiles(jsonFiles);
    final configPath = packageConfigPath ?? findPackageConfigPath(reportRoot);
    final resolver = await Resolver.create(
      packagesPath: configPath,
      sdkRoot: _sdkRoot(),
    );
    final reportOn = [
      p.join(reportRoot, 'lib'),
      if (crossPackageCoverage)
        ..._localLibDirs(
          localPackages ?? localWorkspacePackages(configPath),
          reportRoot,
        ),
    ];
    final lcovContent = hitmap.formatLcov(resolver, reportOn: reportOn);
    File(lcovOutputPath).writeAsStringSync(lcovContent);
  }

  /// Returns the `lib/` directories of [localPackages], excluding
  /// [reportRoot] itself (already in `reportOn`).
  List<String> _localLibDirs(
    List<LocalPackage> localPackages,
    String reportRoot,
  ) {
    final absReportRoot = p.normalize(p.absolute(reportRoot));
    return localPackages
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
