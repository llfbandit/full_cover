import 'dart:io';

import 'package:path/path.dart' as p;

import '../coverage/lcov_record.dart';
import 'html_render_context.dart';

class FolderPageBuilder {
  final HtmlRenderContext _ctx;

  FolderPageBuilder(this._ctx);

  Future<void> writeAll(
    Map<String, List<LcovRecord>> grouped,
    String filesDir,
    String title,
    Map<LcovRecord, String> filePagePaths,
  ) async {
    for (final entry in grouped.entries) {
      final pkgName = entry.key;
      final topFolders = <String, List<LcovRecord>>{};
      for (final r in entry.value) {
        final short = _ctx.splitByPackage(r.sourceFile).shortPath;
        final slash = short.indexOf('/');
        if (slash >= 0) {
          topFolders.putIfAbsent(short.substring(0, slash), () => []).add(r);
        }
      }
      for (final folder in topFolders.entries) {
        await _writeRecursive(
          pkgName: pkgName,
          folderPath: folder.key,
          records: folder.value,
          filesDir: filesDir,
          title: title,
          filePagePaths: filePagePaths,
          backHref: '../index.html',
        );
      }
    }
  }

  Future<void> _writeRecursive({
    required String pkgName,
    required String folderPath,
    required List<LcovRecord> records,
    required String filesDir,
    required String title,
    required Map<LcovRecord, String> filePagePaths,
    required String backHref,
  }) async {
    final prefix = '$folderPath/';

    final directFiles = <LcovRecord>[];
    final subFolderMap = <String, List<LcovRecord>>{};
    for (final r in records) {
      final rel = _ctx
          .splitByPackage(r.sourceFile)
          .shortPath
          .substring(prefix.length);
      final slash = rel.indexOf('/');
      if (slash < 0) {
        directFiles.add(r);
      } else {
        subFolderMap.putIfAbsent(rel.substring(0, slash), () => []).add(r);
      }
    }

    for (final sub in subFolderMap.keys) {
      await _writeRecursive(
        pkgName: pkgName,
        folderPath: '$folderPath/$sub',
        records: subFolderMap[sub]!,
        filesDir: filesDir,
        title: title,
        filePagePaths: filePagePaths,
        backHref: './${_ctx.folderPageName(pkgName, folderPath)}',
      );
    }

    final lF = records.fold(0, (s, r) => s + r.linesFound);
    final lH = records.fold(0, (s, r) => s + r.linesHit);
    final bF = records.fold(0, (s, r) => s + r.branchesFound);
    final bH = records.fold(0, (s, r) => s + r.branchesHit);
    final fF = records.fold(0, (s, r) => s + r.functionsFound);
    final fH = records.fold(0, (s, r) => s + r.functionsHit);
    final lPct = lF == 0 ? 100.0 : lH / lF * 100;
    final bPct = bF == 0 ? 100.0 : bH / bF * 100;
    final fPct = fF == 0 ? 100.0 : fH / fF * 100;
    final headerPath = '$pkgName/$folderPath/';

    final body = StringBuffer();
    body.writeln('<div class="header">');
    body.writeln(
      '<a class="back-link" href="${_ctx.escape(backHref)}">← back</a>',
    );
    body.writeln('<h1>${_ctx.escape(title)}</h1>');
    body.writeln('<h2>${_ctx.escape(headerPath)}</h2>');
    body.writeln('<div class="totals">');
    _ctx.writeMeter(body, 'Lines', lH, lF, lPct, threshold: _ctx.limits.line);
    _ctx.writeMeter(
      body,
      'Branches',
      bH,
      bF,
      bPct,
      threshold: _ctx.limits.branch,
    );
    _ctx.writeMeter(
      body,
      'Functions',
      fH,
      fF,
      fPct,
      threshold: _ctx.limits.function,
    );
    body.writeln('</div>');
    body.writeln('</div>');

    body.writeln('<div class="files">');
    body.writeln('<table>');
    body.writeln(
      '<thead><tr>'
      '<th>File<span class="sort-icon"></span></th>'
      '<th>Lines<span class="sort-icon"></span></th>'
      '<th>Branches<span class="sort-icon"></span></th>'
      '<th>Functions<span class="sort-icon"></span></th>'
      '</tr></thead>',
    );
    body.writeln('<tbody>');

    directFiles.sort(
      (a, b) => _ctx
          .splitByPackage(a.sourceFile)
          .shortPath
          .compareTo(_ctx.splitByPackage(b.sourceFile).shortPath),
    );
    for (final r in directFiles) {
      _ctx.emitFileRow(body, r, '', folderPath, filePagePaths, filesDir, false);
    }
    for (final sub in (subFolderMap.keys.toList()..sort())) {
      final href = './${_ctx.folderPageName(pkgName, '$folderPath/$sub')}';
      _ctx.emitFolderHeaderRow(body, sub, subFolderMap[sub]!, '', href, false);
    }

    body.writeln('</tbody></table>');
    body.writeln('</div>');

    await File(
      p.join(filesDir, _ctx.folderPageName(pkgName, folderPath)),
    ).writeAsString(_ctx.render(headerPath, body.toString()));
  }
}
