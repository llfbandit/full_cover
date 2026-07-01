import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'limits_config.dart';
import 'package_config.dart';

class FullCoverConfig {
  /// Absolute path to the directory containing full_cover.yaml (the workspace root).
  final String workspaceRoot;
  final List<PackageExcludeConfig> packageExcludes;
  final List<String> globalFileExcludes;

  /// output.global — write merged lcov.info at outputDirectory/lcov.info.
  final bool globalLcov;

  /// output.directory — base folder for coverage outputs, relative to workspaceRoot.
  final String outputDirectory;

  /// output.html.global — generate merged HTML report at outputDirectory/htmlDirectory.
  final bool htmlGlobal;

  /// output.html.package — generate HTML report inside each package's coverage/html.
  final bool htmlPackage;

  /// output.html.directory — HTML subfolder relative to outputDirectory.
  final String htmlDirectory;

  /// limits — coverage threshold rules for color-coding the HTML report.
  final LimitsConfig limits;

  /// cross_package_coverage — when true, hits on sibling local packages
  /// during a package's test run are included in its LCOV output.
  final bool crossPackageCoverage;

  const FullCoverConfig({
    required this.workspaceRoot,
    this.packageExcludes = const [],
    this.globalFileExcludes = const [],
    this.globalLcov = true,
    this.outputDirectory = 'coverage',
    this.htmlGlobal = false,
    this.htmlPackage = false,
    this.htmlDirectory = 'html',
    this.limits = const LimitsConfig(),
    this.crossPackageCoverage = true,
  });

  factory FullCoverConfig.fromYaml(
    String content, {
    required String workspaceRoot,
  }) {
    final yaml = loadYaml(content) as YamlMap;

    final rawPkgExcludes = yaml['package_excludes'] as YamlList?;
    final packageExcludes =
        rawPkgExcludes?.map(PackageExcludeConfig.fromYaml).toList() ??
        <PackageExcludeConfig>[];

    final globalFileExcludes = expandPatternList(
      yaml['global_excludes'] as YamlList?,
    );

    final output = yaml['output'] as YamlMap?;
    final globalLcov = output?['global'] as bool? ?? true;
    final outputDirectory = output?['directory'] as String? ?? 'coverage';

    final html = output?['html'] as YamlMap?;
    final htmlGlobal = html?['global'] as bool? ?? false;
    final htmlPackage = html?['package'] as bool? ?? false;
    final htmlDirectory = html?['directory'] as String? ?? 'html';

    final limits = LimitsConfig.fromYaml(yaml['limits'] as YamlMap?);
    final crossPackageCoverage =
        yaml['cross_package_coverage'] as bool? ?? true;

    return FullCoverConfig(
      workspaceRoot: workspaceRoot,
      packageExcludes: packageExcludes,
      globalFileExcludes: globalFileExcludes,
      globalLcov: globalLcov,
      outputDirectory: outputDirectory,
      htmlGlobal: htmlGlobal,
      htmlPackage: htmlPackage,
      htmlDirectory: htmlDirectory,
      limits: limits,
      crossPackageCoverage: crossPackageCoverage,
    );
  }

  factory FullCoverConfig.fromFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw StateError('Config file not found: $filePath');
    }
    final workspaceRoot = p.normalize(p.absolute(p.dirname(filePath)));
    return FullCoverConfig.fromYaml(
      file.readAsStringSync(),
      workspaceRoot: workspaceRoot,
    );
  }
}
