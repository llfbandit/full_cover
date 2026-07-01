import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A package_config.json entry that resolves to a local, on-disk path (as
/// opposed to a pub-cache or SDK entry).
class LocalPackage {
  final String rootPath;
  final String libPath;

  const LocalPackage({required this.rootPath, required this.libPath});
}

/// Returns the `package_config.json` path for [pkgPath].
///
/// In a pub workspace the file lives at the workspace root, not inside each
/// sub-package. Walk up the directory tree until we find one.
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
/// on-disk path, excluding pub-cache/SDK entries.
///
/// In a Dart workspace `package_config.json`, local packages use a relative
/// `rootUri` (e.g. `"../other_pkg/"`). Pub-cache entries use an absolute
/// `file:///…` URI — those are skipped.
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
      if (rootUri == null) continue;
      // Absolute URIs (file://, drive letters, /…) → pub cache or SDK; skip.
      if (Uri.parse(rootUri).isAbsolute) continue;
      final rootPath = p.normalize(p.absolute(p.join(configDir, rootUri)));
      final packageUri = pkg['packageUri'] as String? ?? 'lib/';
      final libPath = p.normalize(p.join(rootPath, packageUri));
      result.add(LocalPackage(rootPath: rootPath, libPath: libPath));
    }
    return result;
  } catch (_) {
    return [];
  }
}
