import 'dart:io';

import 'package:path/path.dart' as p;

import '../coverage/lcov_record.dart';
import 'html_render_context.dart';

class IndexPageBuilder {
  final HtmlRenderContext _ctx;

  IndexPageBuilder(this._ctx);

  Future<void> write(
    Map<String, List<LcovRecord>> groups,
    String outputDir,
    String filesDir,
    String title,
    Map<LcovRecord, String> filePagePaths,
  ) async {
    final records = groups.values.expand((l) => l).toList();
    final totalLines = records.fold(0, (s, r) => s + r.linesFound);
    final hitLines = records.fold(0, (s, r) => s + r.linesHit);
    final totalBranches = records.fold(0, (s, r) => s + r.branchesFound);
    final hitBranches = records.fold(0, (s, r) => s + r.branchesHit);
    final totalFunctions = records.fold(0, (s, r) => s + r.functionsFound);
    final hitFunctions = records.fold(0, (s, r) => s + r.functionsHit);
    final linePct = totalLines == 0 ? 100.0 : hitLines / totalLines * 100;
    final branchPct = totalBranches == 0
        ? 100.0
        : hitBranches / totalBranches * 100;
    final fnPct = totalFunctions == 0
        ? 100.0
        : hitFunctions / totalFunctions * 100;

    final hasTree = groups.length > 1;
    final sortedPackages = groups.keys.toList()..sort();

    final body = StringBuffer();
    body.writeln('<div class="header">');
    body.writeln('<h1>${_ctx.escape(title)}</h1>');
    body.writeln(
      '<p class="generated">Generated ${DateTime.now().toLocal()}</p>',
    );
    body.writeln('<div class="totals">');
    _ctx.writeMeter(
      body,
      'Lines',
      hitLines,
      totalLines,
      linePct,
      threshold: _ctx.limits.line,
    );
    _ctx.writeMeter(
      body,
      'Branches',
      hitBranches,
      totalBranches,
      branchPct,
      threshold: _ctx.limits.branch,
    );
    _ctx.writeMeter(
      body,
      'Functions',
      hitFunctions,
      totalFunctions,
      fnPct,
      threshold: _ctx.limits.function,
    );
    body.writeln('</div>');
    body.writeln('</div>');

    body.writeln('<div class="files">');
    if (hasTree) {
      body.writeln(
        '<div class="table-toolbar">'
        '<a id="toggle-all-packages" href="#">Collapse all</a>'
        '</div>',
      );
    }
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

    for (final pkgName in sortedPackages) {
      final pkgRecords = groups[pkgName]!;
      if (hasTree) {
        _emitPackageHeaderRow(body, pkgName, pkgRecords);
      }
      _emitPackageRows(
        body,
        pkgRecords,
        pkgName,
        filePagePaths,
        outputDir,
        filesDir,
        hasTree,
      );
    }

    body.writeln('</tbody></table>');
    body.writeln('</div>');

    await File(p.join(outputDir, 'index.html')).writeAsString(
      _ctx.render(title, body.toString(), assetsPrefix: 'files/'),
    );
  }

  void _emitPackageHeaderRow(
    StringBuffer body,
    String pkgName,
    List<LcovRecord> records,
  ) {
    final lF = records.fold(0, (s, r) => s + r.linesFound);
    final lH = records.fold(0, (s, r) => s + r.linesHit);
    final bF = records.fold(0, (s, r) => s + r.branchesFound);
    final bH = records.fold(0, (s, r) => s + r.branchesHit);
    final fF = records.fold(0, (s, r) => s + r.functionsFound);
    final fH = records.fold(0, (s, r) => s + r.functionsHit);
    final lPct = lF == 0 ? 100.0 : lH / lF * 100;
    final bPct = bF == 0 ? 100.0 : bH / bF * 100;
    final fPct = fF == 0 ? 100.0 : fH / fF * 100;

    body.write('<tr class="pkg-header" data-group="${_ctx.escape(pkgName)}">');
    body.write(
      '<td><span class="toggle-icon">▼</span> ${_ctx.escape(pkgName)}</td>',
    );
    body.write(
      '<td class="${_ctx.cellClass(lPct, _ctx.limits.line)}" data-value="$lPct">${_ctx.pct(lPct)} <span class="count">$lH/$lF</span></td>',
    );
    body.write(
      '<td class="${_ctx.cellClass(bPct, _ctx.limits.branch)}" data-value="$bPct">${_ctx.pct(bPct)} <span class="count">$bH/$bF</span></td>',
    );
    body.write(
      '<td class="${_ctx.cellClass(fPct, _ctx.limits.function)}" data-value="$fPct">${_ctx.pct(fPct)} <span class="count">$fH/$fF</span></td>',
    );
    body.writeln('</tr>');
  }

  void _emitPackageRows(
    StringBuffer body,
    List<LcovRecord> records,
    String pkgName,
    Map<LcovRecord, String> filePagePaths,
    String fromDir,
    String filesDir,
    bool hasTree,
  ) {
    final folderMap = <String, List<LcovRecord>>{};
    for (final r in records) {
      final short = _ctx.splitByPackage(r.sourceFile).shortPath;
      final slash = short.indexOf('/');
      final key = slash >= 0 ? short.substring(0, slash) : '';
      folderMap.putIfAbsent(key, () => []).add(r);
    }
    for (final r in folderMap[''] ?? []) {
      _ctx.emitFileRow(body, r, pkgName, null, filePagePaths, fromDir, hasTree);
    }
    for (final folder
        in (folderMap.keys.where((k) => k.isNotEmpty).toList()..sort())) {
      final folderPagePath = p.join(
        filesDir,
        _ctx.folderPageName(pkgName, folder),
      );
      final href = p
          .relative(folderPagePath, from: fromDir)
          .replaceAll(r'\', '/');
      _ctx.emitFolderHeaderRow(
        body,
        folder,
        folderMap[folder]!,
        pkgName,
        href,
        hasTree,
      );
    }
  }
}
