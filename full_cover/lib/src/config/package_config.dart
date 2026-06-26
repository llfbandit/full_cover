import 'package:yaml/yaml.dart';

/// A workspace package discovered from pubspec.yaml, with resolved file exclusions.
class PackageConfig {
  final String path;
  final List<String> excludes;

  const PackageConfig({required this.path, this.excludes = const []});
}

/// A config-file entry that maps a package path glob to a list of file/folder exclusions.
class PackageExcludeConfig {
  final String package;
  final List<String> excludes;

  const PackageExcludeConfig({required this.package, this.excludes = const []});

  factory PackageExcludeConfig.fromYaml(dynamic yaml) {
    final map = yaml as YamlMap;
    final rawExcludes = map['excludes'] as YamlList?;
    return PackageExcludeConfig(
      package: map['package'] as String,
      excludes: rawExcludes?.map((e) => e as String).toList() ?? [],
    );
  }
}
