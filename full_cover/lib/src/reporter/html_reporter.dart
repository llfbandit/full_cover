import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../config/limits_config.dart';
import '../coverage/lcov_record.dart';
import 'file_page_builder.dart';
import 'folder_page_builder.dart';
import 'html_render_context.dart';
import 'index_page_builder.dart';

class HtmlReporter {
  String? _css;
  String? _js;
  String? _pageTemplate;

  Future<void> generate({
    required List<LcovRecord> records,
    required String outputDir,
    String title = 'Coverage Report',
    String? rootPath,
    LimitsConfig limits = const LimitsConfig(),
  }) async {
    await Directory(outputDir).create(recursive: true);
    final filesDir = p.join(outputDir, 'files');
    await Directory(filesDir).create(recursive: true);

    _css ??= await _loadAsset('coverage.css');
    _js ??= await _loadAsset('coverage.js');
    _pageTemplate ??= await _loadAsset('page_template.html');

    await File(p.join(filesDir, 'coverage.css')).writeAsString(_css!);
    await File(p.join(filesDir, 'coverage.js')).writeAsString(_js!);

    final ctx = HtmlRenderContext(limits: limits, pageTemplate: _pageTemplate!);

    final groups = <String, List<LcovRecord>>{};
    for (final r in records) {
      groups
          .putIfAbsent(ctx.splitByPackage(r.sourceFile).package, () => [])
          .add(r);
    }
    for (final list in groups.values) {
      list.sort(
        (a, b) => ctx
            .splitByPackage(a.sourceFile)
            .shortPath
            .compareTo(ctx.splitByPackage(b.sourceFile).shortPath),
      );
    }

    final filePagePaths = <LcovRecord, String>{};
    final fileBuilder = FilePageBuilder(ctx);
    for (final r in groups.values.expand((l) => l)) {
      filePagePaths[r] = await fileBuilder.write(r, filesDir, rootPath, title);
    }

    await FolderPageBuilder(
      ctx,
    ).writeAll(groups, filesDir, title, filePagePaths);
    await IndexPageBuilder(
      ctx,
    ).write(groups, outputDir, filesDir, title, filePagePaths);
  }

  static Future<String> _loadAsset(String filename) async {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:full_cover/src/reporter/web/$filename'),
    );
    if (uri == null) {
      throw StateError('Cannot resolve package asset: $filename');
    }
    return File.fromUri(uri).readAsString();
  }
}
