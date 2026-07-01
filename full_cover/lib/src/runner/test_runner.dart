import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../ansi.dart';
import '../config/package_config.dart';
import '../coverage/lcov_converter.dart';
import '../coverage/local_packages.dart';
import '../logger.dart';

class TestRunner {
  final Logger logger;
  final String? concurrency;
  final bool crossPackageCoverage;
  final LcovConverter _converter;

  const TestRunner({
    this.logger = const Logger(),
    this.concurrency,
    this.crossPackageCoverage = true,
  }) : _converter = const LcovConverter();

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
    logger.detail(ansi.cyan('  Running flutter test...'));
    final localPackages = crossPackageCoverage
        ? localWorkspacePackages(findPackageConfigPath(pkgPath))
        : const <LocalPackage>[];
    await _runProcess('flutter', [
      'test',
      '--coverage',
      '--branch-coverage',
      if (concurrency != null) '--concurrency=$concurrency',
      if (crossPackageCoverage) ..._coveragePackageArgs(localPackages),
    ], pkgPath);
  }

  Future<void> _runDart(String pkgPath, String lcovOutputPath) async {
    const tempCoverageDir = '.dart_coverage_temp';
    final tempDir = Directory(p.join(pkgPath, tempCoverageDir));

    // Clean previous run
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);

    // Parsed once and reused for both the args and the LCOV conversion below.
    final configPath = findPackageConfigPath(pkgPath);
    final localPackages = crossPackageCoverage
        ? localWorkspacePackages(configPath)
        : const <LocalPackage>[];

    // Step 1: run dart test with coverage collection
    logger.detail(ansi.cyan('  Running dart test...'));
    await _runProcess('dart', [
      'test',
      '--coverage=$tempCoverageDir',
      '--branch-coverage',
      if (concurrency != null) '--concurrency=$concurrency',
      if (crossPackageCoverage) ..._coveragePackageArgs(localPackages),
    ], pkgPath);

    // Step 2: convert raw coverage JSON to LCOV
    logger.detail(ansi.dim('  Converting coverage to LCOV...'));
    await _converter.convert(
      coverageJsonDir: tempDir.path,
      lcovOutputPath: lcovOutputPath,
      reportRoot: pkgPath,
      crossPackageCoverage: crossPackageCoverage,
      packageConfigPath: configPath,
      localPackages: localPackages,
    );

    // Clean up temp dir
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  }

  /// Builds one `--coverage-package=\bname\b` argument per local package
  /// (this one plus any workspace siblings), instead of a single alternation
  /// regex like `^(a|b)$`.
  List<String> _coveragePackageArgs(List<LocalPackage> localPackages) {
    final names = localPackages.map((pkg) => pkg.name).toSet();
    if (names.isEmpty) return ['--coverage-package=.*'];
    return [
      for (final name in names)
        '--coverage-package=\\b${RegExp.escape(name)}\\b',
    ];
  }

  /// Runs [executable] with [args] in [pkgPath], streaming output live and
  /// throwing on a non-zero exit code.
  Future<void> _runProcess(
    String executable,
    List<String> args,
    String pkgPath,
  ) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: pkgPath,
      runInShell: true,
    );

    // Captured (not just streamed) so failures are diagnosable without -v.
    final captured = logger.isVerbose ? null : StringBuffer();
    final stdoutDone = _forward(process.stdout, captured);
    final stderrDone = _forward(process.stderr, captured);

    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    if (exitCode != 0) {
      final detail = captured != null
          ? '\n${captured.toString().trimRight()}'
          : '';
      throw StateError(
        '$executable ${args.first} failed (exit $exitCode) in $pkgPath$detail',
      );
    }
  }

  /// Forwards [stream] lines to the logger, buffering into [sink] if given.
  Future<void> _forward(Stream<List<int>> stream, StringBuffer? sink) {
    return stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          sink?.writeln(line);
          logger.detail(line);
        });
  }
}
