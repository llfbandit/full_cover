import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../ansi.dart';
import '../config/package_config.dart';
import '../coverage/lcov_converter.dart';
import '../logger.dart';

class TestRunner {
  final Logger logger;
  final String? concurrency;
  final LcovConverter _converter;

  const TestRunner({this.logger = const Logger(), this.concurrency})
    : _converter = const LcovConverter();

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
    await _runProcess('flutter', [
      'test',
      '--coverage',
      '--branch-coverage',
      if (concurrency != null) '--concurrency=$concurrency',
    ], pkgPath);
  }

  Future<void> _runDart(String pkgPath, String lcovOutputPath) async {
    const tempCoverageDir = '.dart_coverage_temp';
    final tempDir = Directory(p.join(pkgPath, tempCoverageDir));

    // Clean previous run
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);

    // Step 1: run dart test with coverage collection
    logger.detail(ansi.cyan('  Running dart test...'));
    await _runProcess('dart', [
      'test',
      '--coverage=$tempCoverageDir',
      '--branch-coverage',
      if (concurrency != null) '--concurrency=$concurrency',
    ], pkgPath);

    // Step 2: convert raw coverage JSON to LCOV
    logger.detail(ansi.dim('  Converting coverage to LCOV...'));
    await _converter.convert(
      coverageJsonDir: tempDir.path,
      lcovOutputPath: lcovOutputPath,
      reportRoot: pkgPath,
    );

    // Clean up temp dir
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
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

    // Capture output (and stream it live when verbose). Both pipes are drained
    // concurrently so the child never blocks on a full OS buffer.
    final captured = StringBuffer();
    final stdoutDone = _forward(process.stdout, captured);
    final stderrDone = _forward(process.stderr, captured);

    final exitCode = await process.exitCode;
    await stdoutDone;
    await stderrDone;

    if (exitCode != 0) {
      // When verbose the output already streamed live; otherwise include it so
      // the failure is diagnosable without re-running with -v.
      final detail = logger.isVerbose
          ? ''
          : '\n${captured.toString().trimRight()}';
      throw StateError(
        '$executable ${args.first} failed (exit $exitCode) in $pkgPath$detail',
      );
    }
  }

  /// Consumes a process output [stream], capturing every line into [sink] and
  /// also forwarding it to the logger live when verbose.
  Future<void> _forward(Stream<List<int>> stream, StringBuffer sink) {
    return stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          sink.writeln(line);
          logger.detail(line); // streamed live only when verbose
        });
  }
}
