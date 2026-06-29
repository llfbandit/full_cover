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
    final expanded = expandPatternList(map['excludes'] as YamlList?);
    return PackageExcludeConfig(
      package: map['package'] as String,
      excludes: expanded.isEmpty ? const ['**'] : expanded,
    );
  }
}

/// Expands a YAML pattern list into a flat [List<String>].
///
/// Each entry can be a plain string (including negations like `"!foo"`) or a
/// map with a `pattern` key and an optional `except` key that expands into
/// negation entries:
///
/// ```yaml
/// - "**/*.g.dart"
/// - pattern: "**/ui/**"
///   except:
///     - "**_bloc.dart"
/// ```
///
/// becomes `["**/*.g.dart", "**/ui/**", "!**_bloc.dart"]`.
List<String> expandPatternList(YamlList? items) {
  if (items == null) return const [];
  final result = <String>[];
  for (final item in items) {
    if (item is String) {
      result.add(item);
    } else if (item is YamlMap) {
      result.add(item['pattern'] as String);
      final except = item['except'];
      if (except is String) {
        result.add('!$except');
      } else if (except is YamlList) {
        for (final e in except) {
          result.add('!${e as String}');
        }
      }
    }
  }
  return result;
}
