import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A package_config.json entry that resolves to a local, on-disk path (as
/// opposed to a pub-cache or SDK entry).
class LocalPackage {
  final String name;
  final String rootPath;
  final String libPath;

  const LocalPackage({
    required this.name,
    required this.rootPath,
    required this.libPath,
  });
}

/// Returns the `package_config.json` path for [pkgPath], walking up the
/// directory tree since in a pub workspace it lives at the workspace root.
String findPackageConfigPath(String pkgPath) {
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

/// Returns the packages declared in [configPath] that resolve to a local
/// on-disk path (relative `rootUri`), excluding pub-cache/SDK entries
/// (absolute `file:///...` URIs).
List<LocalPackage> localWorkspacePackages(String configPath) {
  final file = File(configPath);
  if (!file.existsSync()) return [];
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final packages =
        (json['packages'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final configDir = p.dirname(configPath); // the .dart_tool/ directory
    final result = <LocalPackage>[];
    for (final pkg in packages) {
      final rootUri = pkg['rootUri'] as String?;
      final name = pkg['name'] as String?;
      if (rootUri == null || name == null) continue;
      // Absolute URIs (file://, drive letters, /…) → pub cache or SDK; skip.
      if (Uri.parse(rootUri).isAbsolute) continue;
      final rootPath = p.normalize(p.absolute(p.join(configDir, rootUri)));
      final packageUri = pkg['packageUri'] as String? ?? 'lib/';
      final libPath = p.normalize(p.join(rootPath, packageUri));
      result.add(
        LocalPackage(name: name, rootPath: rootPath, libPath: libPath),
      );
    }
    return result;
  } catch (_) {
    return [];
  }
}
