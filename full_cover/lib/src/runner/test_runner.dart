import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config/package_config.dart';

class TestRunner {
  final bool verbose;
  final String? concurrency;

  const TestRunner({this.verbose = false, this.concurrency});

  /// Runs tests for [pkg] and returns the path to the generated lcov.info.
  Future<String> run(PackageConfig pkg) async {
    final pkgPath = p.normalize(p.absolute(pkg.path));
    final lcovPath = p.join(pkgPath, 'coverage', 'lcov.info');

    if (_isFlutterPackage(pkgPath)) {
      await _runFlutter(pkgPath);
    } else {
      await _runDart(pkgPath, lcovPath);
    }

    return lcovPath;
  }

  /// Returns true when the package's pubspec.yaml declares a Flutter dependency.
  bool _isFlutterPackage(String pkgPath) {
    final pubspec = File(p.join(pkgPath, 'pubspec.yaml'));
    if (!pubspec.existsSync()) return false;
    try {
      final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
      final deps = yaml['dependencies'] as YamlMap?;
      final devDeps = yaml['dev_dependencies'] as YamlMap?;
      return deps?.containsKey('flutter') == true ||
          devDeps?.containsKey('flutter') == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _runFlutter(String pkgPath) async {
    _log('Running flutter test in $pkgPath...');
    final result = await Process.run(
      'flutter',
      [
        'test',
        '--coverage',
        '--branch-coverage',
        if (concurrency != null) '--concurrency=$concurrency',
      ],
      workingDirectory: pkgPath,
      runInShell: true,
    );
    _logOutput(result);
    if (result.exitCode != 0) {
      throw StateError(
        'flutter test failed (exit ${result.exitCode}) in $pkgPath',
      );
    }
  }

  Future<void> _runDart(String pkgPath, String lcovOutputPath) async {
    const tempCoverageDir = '.dart_coverage_temp';
    final tempPath = p.join(pkgPath, tempCoverageDir);

    // Clean previous run
    final tempDir = Directory(tempPath);
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);

    // Step 1: run dart test with coverage collection
    _log('Running dart test in $pkgPath...');
    final testResult = await Process.run(
      'dart',
      [
        'test',
        '--coverage=$tempCoverageDir',
        '--branch-coverage',
        if (concurrency != null) '--concurrency=$concurrency',
      ],
      workingDirectory: pkgPath,
      runInShell: true,
    );
    _logOutput(testResult);
    if (testResult.exitCode != 0) {
      throw StateError(
        'dart test failed (exit ${testResult.exitCode}) in $pkgPath',
      );
    }

    // Step 2: convert raw coverage JSON to LCOV via coverage package API
    final jsonFiles = tempDir.existsSync()
        ? tempDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.json'))
              .toList()
        : <File>[];

    final lcovDir = Directory(p.dirname(lcovOutputPath));
    lcovDir.createSync(recursive: true);

    if (jsonFiles.isEmpty) {
      File(lcovOutputPath).writeAsStringSync('');
      return;
    }

    _log('Converting coverage to LCOV...');
    final hitmap = await HitMap.parseFiles(jsonFiles);
    final resolver = await Resolver.create(
      packagesPath: _packageConfigPath(pkgPath),
      sdkRoot: _sdkRoot(),
    );
    final lcovContent = hitmap.formatLcov(
      resolver,
      reportOn: [p.join(pkgPath, 'lib')],
    );
    File(lcovOutputPath).writeAsStringSync(lcovContent);

    // Clean up temp dir
    tempDir.deleteSync(recursive: true);
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

  void _log(String message) {
    if (verbose) print(message);
  }

  void _logOutput(ProcessResult result) {
    if (!verbose) return;
    if (result.stdout.toString().isNotEmpty) print(result.stdout);
    if (result.stderr.toString().isNotEmpty) print(result.stderr);
  }
}
