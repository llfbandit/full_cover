import 'dart:convert';
import 'dart:io';

import 'package:full_cover/src/coverage/local_packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('fc_localpkg_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  test('findPackageConfigPath walks up to the workspace root', () {
    Directory(p.join(tempDir.path, '.dart_tool')).createSync();
    final expected = p.join(tempDir.path, '.dart_tool', 'package_config.json');
    File(expected).writeAsStringSync('{}');

    final sub = Directory(p.join(tempDir.path, 'pkg_a'))..createSync();
    expect(findPackageConfigPath(sub.path), expected);
  });

  test(
    'localWorkspacePackages returns local entries and skips pub-cache ones',
    () {
      Directory(p.join(tempDir.path, '.dart_tool')).createSync();
      final configPath = p.join(
        tempDir.path,
        '.dart_tool',
        'package_config.json',
      );
      File(configPath).writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'root_pkg', 'rootUri': '../', 'packageUri': 'lib/'},
            {'name': 'pkg_a', 'rootUri': '../pkg_a/', 'packageUri': 'lib/'},
            {
              'name': 'collection',
              'rootUri': 'file:///pub-cache/collection-1.0/',
              'packageUri': 'lib/',
            },
          ],
        }),
      );

      final rootPaths = localWorkspacePackages(
        configPath,
      ).map((pkg) => pkg.rootPath);
      expect(
        rootPaths,
        containsAll([tempDir.path, p.join(tempDir.path, 'pkg_a')]),
      );
      expect(rootPaths, hasLength(2));
    },
  );
}
