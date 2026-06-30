import 'dart:io';

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

class FullCoverRunner {
  final LogLevel level;
  final bool skipTests;
  final String? concurrency;
  final Logger logger;

  FullCoverRunner({
    this.level = LogLevel.normal,
    this.skipTests = false,
    this.concurrency,
    Logger? logger,
  }) : logger = logger ?? Logger(level: level);

  Future<void> run(FullCoverConfig config) async {
    final packages = _discoverPackages(
      config.workspaceRoot,
      config.packageExcludes,
    );
    logger.info(ansi.bold('Discovered ${packages.length} package(s).'));

    // Packages are independent, so process them concurrently. The bound keeps
    // us from spawning more test processes than the machine can usefully run
    // (each package's `dart test` already honours its own --concurrency).
    final results = await _mapBounded(
      packages,
      Platform.numberOfProcessors,
      (pkg) => _processPackage(pkg, config, packages),
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
        logger.info(ansi.dim('  Generating global HTML → $htmlOut'));
        await HtmlReporter().generate(
          records: merged,
          outputDir: htmlOut,
          title: 'Global Coverage',
          limits: config.limits,
        );
      }
    }

    logger.info('\n${ansi.green(ansi.bold('✓ Done.'))}');
  }

  /// Runs the full pipeline for [pkg], returning its filtered records or null
  /// when there was nothing to process.
  ///
  /// Verbose detail is captured into a per-package buffer so concurrent packages
  /// don't interleave. When verbose, that buffer is flushed as a single labeled
  /// block; otherwise a one-line summary is emitted as the package finishes.
  Future<List<LcovRecord>?> _processPackage(
    PackageConfig pkg,
    FullCoverConfig config,
    List<PackageConfig> allPackages,
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
        allPackages,
      );
      if (logger.isVerbose) {
        _flushBlock(name, buffer);
      } else {
        _logSummary(name, records);
      }
      return records;
    } catch (_) {
      // Surface whatever detail was captured before letting the error propagate
      // (the test output itself rides along on the thrown StateError).
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
  void _logSummary(String name, List<LcovRecord>? records) {
    if (records == null) {
      logger.warn('  ${ansi.yellow('⚠')} $name — no coverage data, skipping');
      return;
    }
    var found = 0;
    var hit = 0;
    for (final r in records) {
      found += r.linesFound;
      hit += r.linesHit;
    }
    final pct = found == 0 ? '—' : '${(100 * hit / found).toStringAsFixed(1)}%';
    logger.info('  ${ansi.green('✓')} ${name.padRight(24)} $pct');
  }

  Future<List<LcovRecord>?> _runPipeline(
    PackageConfig pkg,
    String pkgPath,
    FullCoverConfig config,
    Logger log,
    List<PackageConfig> allPackages,
  ) async {
    log.detail(ansi.dim('Processing $pkgPath'));

    final parser = LcovParser();
    List<LcovRecord> records;

    if (skipTests) {
      final lcovFile = File(p.join(pkgPath, 'coverage', 'lcov.info'));
      if (!lcovFile.existsSync()) {
        log.detail(ansi.yellow('  No coverage data at ${lcovFile.path}.'));
        records = [];
      }
      records = parser.parse(lcovFile.readAsStringSync());
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

    // Drop sibling-package records that should be excluded under their own
    // package config, so cross-package hits don't re-introduce excluded files.
    if (config.crossPackageCoverage) {
      records = LcovFilter.filterSiblingExcludes(
        records: records,
        currentPkgPath: pkgPath,
        siblings: allPackages.map(
          (pkg) => (path: pkg.path, excludes: pkg.excludes),
        ),
        globalExcludes: config.globalFileExcludes,
      );
    }

    final filePatterns = [...config.globalFileExcludes, ...pkg.excludes];

    // Inject zero-coverage for uncovered files, skipping excluded ones so we
    // never read a file that the filter would discard anyway.
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

    // Replace VM line-level branch data with condition-level branch data
    final branchAnalyzer = BranchAnalyzer();
    records = records
        .map(branchAnalyzer.analyze)
        .where(
          (r) =>
              r.lines.isNotEmpty ||
              r.functions.isNotEmpty ||
              r.branches.isNotEmpty,
        )
        .toList();

    if (config.htmlPackage && records.isNotEmpty) {
      final pkgOutDir = p.join(pkgPath, 'coverage', 'html');
      log.detail(ansi.dim('  Generating per-package HTML → $pkgOutDir'));
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

  /// Applies [task] to each of [items] with at most [maxConcurrent] running at
  /// once, preserving input order in the returned results.
  Future<List<T>> _mapBounded<S, T>(
    List<S> items,
    int maxConcurrent,
    Future<T> Function(S item) task,
  ) async {
    final results = List<T?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= items.length) return;
        results[index] = await task(items[index]);
      }
    }

    final workerCount = maxConcurrent < items.length
        ? maxConcurrent
        : items.length;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    return results.cast<T>();
  }

  Future<void> clean(FullCoverConfig config) async {
    final absOutputDir = p.normalize(
      p.join(config.workspaceRoot, config.outputDirectory),
    );
    await _deleteIfExists(absOutputDir);

    final packages = _discoverPackages(
      config.workspaceRoot,
      config.packageExcludes,
    );
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

  /// Reads the workspace [pubspec.yaml] and returns one [PackageConfig] per
  /// discovered package, with file exclusions resolved from [excludeConfigs].
  ///
  /// The root package (`.`) is always included. Sub-packages come from the
  /// `workspace:` list if present, otherwise from `path:` entries in
  /// `dependencies`, `dev_dependencies`, and `dependency_overrides`.
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

      // excludes == ['**'] with no negations means "skip entirely" — avoids
      // running tests on packages the user has excluded without exceptions.
      if (excludes.length == 1 && excludes.first == '**') continue;

      result.add(PackageConfig(path: pkgPath, excludes: excludes));
    }

    return result;
  }
}
