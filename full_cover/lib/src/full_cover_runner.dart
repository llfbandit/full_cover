import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config/config.dart';
import 'config/package_config.dart';
import 'coverage/branch_analyzer.dart';
import 'coverage/lcov_filter.dart';
import 'coverage/lcov_injector.dart';
import 'coverage/lcov_merger.dart';
import 'coverage/lcov_parser.dart';
import 'coverage/lcov_record.dart';
import 'reporter/html_reporter.dart';
import 'runner/test_runner.dart';

class FullCoverRunner {
  final bool verbose;
  final bool skipTests;
  final String? concurrency;

  const FullCoverRunner({
    this.verbose = false,
    this.skipTests = false,
    this.concurrency,
  });

  Future<void> run(FullCoverConfig config) async {
    final runner = TestRunner(verbose: verbose, concurrency: concurrency);
    final parser = LcovParser();
    final branchAnalyzer = BranchAnalyzer();
    final filter = LcovFilter();
    final injector = LcovInjector();
    final merger = LcovMerger();
    final reporter = HtmlReporter();

    final packages = _discoverPackages(
      config.workspaceRoot,
      config.packageExcludes,
    );
    _log('Discovered ${packages.length} package(s).');

    final allPackageRecords = <List<LcovRecord>>[];

    for (final pkg in packages) {
      final pkgPath = p.normalize(p.absolute(pkg.path));
      _log('Processing package: $pkgPath');

      List<LcovRecord> records;

      if (skipTests) {
        final lcovFile = File(p.join(pkgPath, 'coverage', 'lcov.info'));
        if (!lcovFile.existsSync()) {
          _log('  No coverage data at ${lcovFile.path}, skipping.');
          continue;
        }
        records = parser.parse(lcovFile.readAsStringSync());
      } else {
        final lcovPath = await runner.run(pkg);
        records = parser.parse(File(lcovPath).readAsStringSync());
      }

      // Flutter's lcov.info uses relative SF: paths (e.g. lib/src/foo.dart).
      // Resolve them to absolute paths so all downstream code works uniformly.
      records = records.map((r) {
        if (p.isAbsolute(r.sourceFile)) return r;
        return r.copyWith(
          sourceFile: p.normalize(p.join(pkgPath, r.sourceFile)),
        );
      }).toList();

      _log('  Parsed ${records.length} source records.');

      // Inject zero-coverage files before filtering so excludes also apply to them
      records = await injector.inject(records, pkgPath);
      _log('  After injection: ${records.length} records.');

      // Replace VM line-level branch data with condition-level branch data
      records = records.map(branchAnalyzer.analyze).toList();

      records = filter.apply(
        records: records,
        filePatterns: [...config.globalFileExcludes, ...pkg.excludes],
        packagePath: pkgPath,
      );
      _log('  After filtering: ${records.length} records.');

      if (config.htmlPackage && records.isNotEmpty) {
        final pkgOutDir = p.join(pkgPath, 'coverage', 'html');
        _log('  Generating per-package HTML → $pkgOutDir');
        await reporter.generate(
          records: records,
          outputDir: pkgOutDir,
          title: p.basename(pkgPath),
          rootPath: pkgPath,
          limits: config.limits,
        );
      }

      allPackageRecords.add(records);
    }

    if (allPackageRecords.isEmpty) return;

    if (config.globalLcov || config.htmlGlobal) {
      _log('Merging all packages...');
      final merged = merger.merge(allPackageRecords);

      final absOutputDir = p.normalize(
        p.join(config.workspaceRoot, config.outputDirectory),
      );

      if (config.globalLcov) {
        final lcovOut = p.join(absOutputDir, 'lcov.info');
        _log('Writing merged lcov → $lcovOut');
        await Directory(absOutputDir).create(recursive: true);
        final lcovContent = merged.map((r) => r.toInfoString()).join('\n');
        await File(lcovOut).writeAsString(lcovContent);
      }

      if (config.htmlGlobal) {
        final htmlOut = p.join(absOutputDir, config.htmlDirectory);
        _log('Generating global HTML → $htmlOut');
        await reporter.generate(
          records: merged,
          outputDir: htmlOut,
          title: 'Global Coverage',
          limits: config.limits,
        );
      }
    }

    _log('Done.');
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
      _log('Removing $path');
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
          for (final section in ['dependencies', 'dev_dependencies', 'dependency_overrides']) {
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

    return paths.map((pkgPath) {
      final excludes = <String>[];
      // Relative path from workspace root — matched against package: globs.
      final rel = p.relative(pkgPath, from: workspaceRoot);
      final key = rel == '.' ? '.' : rel.replaceAll(r'\', '/');

      for (final ec in excludeConfigs) {
        final glob = Glob(ec.package);
        if (glob.matches(key) || glob.matches(p.basename(pkgPath))) {
          excludes.addAll(ec.excludes);
        }
      }
      return PackageConfig(path: pkgPath, excludes: excludes);
    }).toList();
  }

  void _log(String message) {
    if (verbose) print(message);
  }
}
