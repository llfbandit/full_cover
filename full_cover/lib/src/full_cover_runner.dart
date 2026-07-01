import 'dart:io';
import 'dart:isolate';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'ansi.dart';
import 'config/config.dart';
import 'config/package_config.dart';
import 'coverage/branch_analyzer.dart';
import 'coverage/lcov_filter.dart';
import 'coverage/lcov_injector.dart';
import 'coverage/lcov_merger.dart';
import 'coverage/lcov_parser.dart';
import 'coverage/lcov_record.dart';
import 'logger.dart';
import 'reporter/html_reporter.dart';
import 'runner/test_runner.dart';
import 'util/map_bounded.dart';

class FullCoverRunner {
  final LogLevel level;
  final bool skipTests;
  final String? concurrency;
  final int packageConcurrency;
  final Logger logger;

  FullCoverRunner({
    this.level = LogLevel.normal,
    this.skipTests = false,
    this.concurrency,
    this.packageConcurrency = 2,
    Logger? logger,
  }) : logger = logger ?? Logger(level: level);

  Future<void> run(FullCoverConfig config) async {
    final stopwatch = Stopwatch()..start();
    try {
      // Includes fully-excluded packages so cross-package hits landing in
      // them are attributed correctly instead of mistaken for the current
      // package's own files (see [_isSkipped]).
      final allPackages = _discoverPackages(
        config.workspaceRoot,
        config.packageExcludes,
      );
      final packages = allPackages.where((pkg) => !_isSkipped(pkg)).toList();
      logger.info(ansi.bold('Discovered ${packages.length} package(s).'));

      // Computed once and reused by every package's own pipeline call below.
      final siblingPatterns = LcovFilter.prepareSiblingPatterns(
        siblings: allPackages.map(
          (pkg) => (path: pkg.path, excludes: pkg.excludes),
        ),
        globalExcludes: config.globalFileExcludes,
      );

      final results = await mapBounded(
        packages,
        packages.isEmpty ? 1 : packageConcurrency.clamp(1, packages.length),
        (pkg) => _processPackage(pkg, config, siblingPatterns),
      );
      final allPackageRecords = [for (final records in results) ?records];

      if (allPackageRecords.isEmpty) return;

      if (config.globalLcov || config.htmlGlobal) {
        logger.info('\n${ansi.header('Merging all packages')}');
        final merged = LcovMerger().merge(allPackageRecords);

        final absOutputDir = p.normalize(
          p.join(config.workspaceRoot, config.outputDirectory),
        );

        if (config.globalLcov) {
          final lcovOut = p.join(absOutputDir, 'lcov.info');
          logger.info(ansi.dim('  Writing merged lcov → $lcovOut'));
          await Directory(absOutputDir).create(recursive: true);
          final lcovContent = merged.map((r) => r.toInfoString()).join('\n');
          await File(lcovOut).writeAsString(lcovContent);
        }

        if (config.htmlGlobal) {
          final htmlOut = p.join(absOutputDir, config.htmlDirectory);
          logger.info(
            ansi.dim(
              '  Generating global HTML → ${p.join(htmlOut, 'index.html')}',
            ),
          );
          await HtmlReporter().generate(
            records: merged,
            outputDir: htmlOut,
            title: 'Global Coverage',
            limits: config.limits,
          );
        }
      }

      logger.info('\n${ansi.green(ansi.bold('✓ Done.'))}');
    } finally {
      logger.info(
        ansi.dim('Completed in ${_formatDuration(stopwatch.elapsed)}'),
      );
    }
  }

  /// Formats [duration] as e.g. `1m 05s` or `12.3s`.
  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) {
      return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
    }
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  /// Runs the full pipeline for [pkg], returning its filtered records or null
  /// when there was nothing to process.
  ///
  /// Verbose detail is captured into a per-package buffer. When verbose, that
  /// buffer is flushed as a single labeled block; otherwise a one-line summary
  /// is emitted as the package finishes.
  Future<List<LcovRecord>?> _processPackage(
    PackageConfig pkg,
    FullCoverConfig config,
    List<SiblingPattern> siblingPatterns,
  ) async {
    final buffer = StringBuffer();
    final pkgLogger = Logger(level: level, sink: buffer.writeln);
    final pkgPath = p.normalize(p.absolute(pkg.path));
    final name = p.basename(pkgPath);
    try {
      final records = await _runPipeline(
        pkg,
        pkgPath,
        config,
        pkgLogger,
        siblingPatterns,
      );
      if (logger.isVerbose) {
        _flushBlock(name, buffer);
      } else {
        _logSummary(name, config, records);
      }
      return records;
    } catch (_) {
      // Surface captured detail before the error propagates.
      _flushBlock(name, buffer);
      rethrow;
    }
  }

  /// Flushes a package's captured verbose output as one labeled block.
  void _flushBlock(String name, StringBuffer buffer) {
    if (buffer.isEmpty) return;
    logger.info('\n${ansi.header('━━━━━ $name ━━━━━')}');
    logger.info(buffer.toString().trimRight());
  }

  /// Emits a one-line normal-mode summary for a finished package.
  void _logSummary(
    String name,
    FullCoverConfig config,
    List<LcovRecord>? records,
  ) {
    if (records == null) {
      logger.warn('  ${ansi.yellow('⚠')} $name — no coverage data, skipping');
      return;
    }

    if (config.crossPackageCoverage) {
      logger.info('  ${ansi.green('✓')} ${name.padRight(24)}');
    } else {
      var found = 0;
      var hit = 0;
      for (final r in records) {
        found += r.linesFound;
        hit += r.linesHit;
      }
      final pct = found == 0
          ? '—'
          : '${(100 * hit / found).toStringAsFixed(1)}%';

      logger.info('  ${ansi.green('✓')} ${name.padRight(24)} $pct');
    }
  }

  Future<List<LcovRecord>?> _runPipeline(
    PackageConfig pkg,
    String pkgPath,
    FullCoverConfig config,
    Logger log,
    List<SiblingPattern> siblingPatterns,
  ) async {
    log.detail(ansi.dim('Processing $pkgPath'));

    final parser = LcovParser();
    List<LcovRecord> records;

    if (skipTests) {
      final lcovFile = File(p.join(pkgPath, 'coverage', 'lcov.info'));
      if (!lcovFile.existsSync()) {
        log.detail(ansi.yellow('  No coverage data at ${lcovFile.path}.'));
        records = [];
      } else {
        records = parser.parse(lcovFile.readAsStringSync());
      }
    } else {
      final testDir = Directory(p.join(pkgPath, 'test'));
      if (!testDir.existsSync()) {
        log.detail(ansi.yellow('  No test/ directory.'));
        records = [];
      } else {
        final lcovPath = await TestRunner(
          logger: log,
          concurrency: concurrency,
          crossPackageCoverage: config.crossPackageCoverage,
        ).run(pkg);
        records = parser.parse(File(lcovPath).readAsStringSync());
      }
    }

    // Flutter's lcov.info uses relative SF: paths (e.g. lib/src/foo.dart).
    // Resolve them to absolute paths so all downstream code works uniformly.
    records = records.map((r) {
      if (p.isAbsolute(r.sourceFile)) return r;
      return r.copyWith(sourceFile: p.normalize(p.join(pkgPath, r.sourceFile)));
    }).toList();

    log.detail(ansi.dim('  Parsed ${records.length} source records.'));

    // Drop cross-package hits excluded under their own package's config.
    if (config.crossPackageCoverage) {
      records = LcovFilter.filterSiblingExcludes(
        records: records,
        currentPkgPath: pkgPath,
        siblingPatterns: siblingPatterns,
      );
    }

    final filePatterns = [...config.globalFileExcludes, ...pkg.excludes];

    // Inject zero-coverage for uncovered files, skipping excluded ones.
    records = await LcovInjector().inject(
      records,
      pkgPath,
      filePatterns: filePatterns,
    );
    log.detail(ansi.dim('  After injection: ${records.length} records.'));

    // Filter before branch analysis so the AST parser never runs on excluded files.
    records = LcovFilter().apply(
      records: records,
      filePatterns: filePatterns,
      packagePath: pkgPath,
    );
    log.detail(ansi.dim('  After filtering: ${records.length} records.'));

    // Replace VM line-level branch data with condition-level branch data.
    // Each file's AST parse is independent and CPU-bound, so it's spread
    // across isolates rather than run sequentially on the main one — the
    // per-record payload is just source-file path + int line/branch data,
    // so isolate message-passing overhead stays small relative to the parse.
    final analyzed = await mapBounded(
      records,
      Platform.numberOfProcessors,
      (r) => Isolate.run(() => BranchAnalyzer().analyze(r)),
    );
    records = analyzed
        .where(
          (r) =>
              r.lines.isNotEmpty ||
              r.functions.isNotEmpty ||
              r.branches.isNotEmpty,
        )
        .toList();

    if (config.htmlPackage && records.isNotEmpty) {
      final pkgOutDir = p.join(pkgPath, 'coverage', 'html');
      log.detail(
        ansi.dim(
          '  Generating per-package HTML → ${p.join(pkgOutDir, 'index.html')}',
        ),
      );
      await HtmlReporter().generate(
        records: records,
        outputDir: pkgOutDir,
        title: p.basename(pkgPath),
        rootPath: pkgPath,
        limits: config.limits,
      );
    }

    return records;
  }

  Future<void> clean(FullCoverConfig config) async {
    final absOutputDir = p.normalize(
      p.join(config.workspaceRoot, config.outputDirectory),
    );
    await _deleteIfExists(absOutputDir);

    final packages = _discoverPackages(
      config.workspaceRoot,
      config.packageExcludes,
    ).where((pkg) => !_isSkipped(pkg));
    for (final pkg in packages) {
      final pkgCoverageDir = p.join(
        p.normalize(p.absolute(pkg.path)),
        'coverage',
      );
      await _deleteIfExists(pkgCoverageDir);
    }
  }

  Future<void> _deleteIfExists(String path) async {
    final dir = Directory(path);
    if (dir.existsSync()) {
      logger.info(ansi.dim('Removing $path'));
      await dir.delete(recursive: true);
    }
  }

  /// True when the user excluded [pkg] entirely (`excludes == ['**']`).
  /// Its tests are skipped, but [_discoverPackages] still returns it so
  /// cross-package hits landing in it are dropped rather than mistaken for
  /// the current package's own files.
  bool _isSkipped(PackageConfig pkg) =>
      pkg.excludes.length == 1 && pkg.excludes.first == '**';

  /// Reads the workspace [pubspec.yaml] and returns one [PackageConfig] per
  /// discovered package (root plus `workspace:`/`path:` dependencies), with
  /// excludes resolved from [excludeConfigs]. Includes fully-excluded
  /// packages (see [_isSkipped]) — callers filter those out themselves.
  List<PackageConfig> _discoverPackages(
    String workspaceRoot,
    List<PackageExcludeConfig> excludeConfigs,
  ) {
    final pubspecFile = File(p.join(workspaceRoot, 'pubspec.yaml'));
    final paths = <String>[workspaceRoot]; // root is always a package

    if (pubspecFile.existsSync()) {
      try {
        final yaml = loadYaml(pubspecFile.readAsStringSync()) as YamlMap;
        final workspace = yaml['workspace'] as YamlList?;
        if (workspace != null) {
          for (final entry in workspace) {
            paths.add(p.normalize(p.join(workspaceRoot, entry as String)));
          }
        } else {
          for (final section in [
            'dependencies',
            'dev_dependencies',
            'dependency_overrides',
          ]) {
            final deps = yaml[section] as YamlMap?;
            if (deps == null) continue;
            for (final value in deps.values) {
              if (value is YamlMap) {
                final path = value['path'] as String?;
                if (path != null) {
                  paths.add(p.normalize(p.join(workspaceRoot, path)));
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    final result = <PackageConfig>[];

    for (final pkgPath in paths) {
      // Relative path from workspace root — matched against package globs.
      final rel = p.relative(pkgPath, from: workspaceRoot);
      final key = rel == '.' ? '.' : rel.replaceAll(r'\', '/');

      final excludes = <String>[];
      for (final ec in excludeConfigs) {
        final glob = Glob(ec.package);
        if (glob.matches(key) || glob.matches(p.basename(pkgPath))) {
          excludes.addAll(ec.excludes);
        }
      }

      result.add(PackageConfig(path: pkgPath, excludes: excludes));
    }

    return result;
  }
}
