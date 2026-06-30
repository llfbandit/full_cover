import 'dart:io';

import 'package:path/path.dart' as p;

import '../coverage/lcov_record.dart';
import 'html_render_context.dart';

class FilePageBuilder {
  final HtmlRenderContext _ctx;

  FilePageBuilder(this._ctx);

  Future<String> write(
    LcovRecord record,
    String outputDir,
    String? rootPath,
    String title,
  ) async {
    final split = _ctx.splitByPackage(record.sourceFile);
    final headerPath = split.package.isNotEmpty
        ? '${split.package}/${split.shortPath}'
        : _ctx.displayPath(record.sourceFile, rootPath);
    final safeFileName = headerPath.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final pageFile = File(p.join(outputDir, '$safeFileName.html'));

    List<String> sourceLines;
    try {
      sourceLines = File(record.sourceFile).readAsLinesSync();
    } catch (_) {
      sourceLines = [];
    }

    final lineHits = {for (final l in record.lines) l.line: l.hits};
    final branchLines = <int, List<BranchData>>{};
    for (final br in record.branches) {
      branchLines.putIfAbsent(br.line, () => []).add(br);
    }

    final lPct = record.linesFound == 0
        ? 100.0
        : record.linesHit / record.linesFound * 100;
    final bPct = record.branchesFound == 0
        ? 100.0
        : record.branchesHit / record.branchesFound * 100;
    final fPct = record.functionsFound == 0
        ? 100.0
        : record.functionsHit / record.functionsFound * 100;

    final parts = split.shortPath.split('/');
    final backHref = parts.length > 1
        ? './${_ctx.folderPageName(split.package, parts.sublist(0, parts.length - 1).join('/'))}'
        : '../index.html';

    final body = StringBuffer();
    body.writeln('<div class="header">');
    body.writeln(
      '<div class="nav-links">'
      '<a class="back-link" href="${_ctx.escape(backHref)}">← back</a>'
      '<a class="back-link" href="../index.html">index</a>'
      '</div>',
    );
    body.writeln('<h1>${_ctx.escape(title)}</h1>');
    body.writeln('<h2>${_ctx.escape(headerPath)}</h2>');
    body.writeln('<div class="totals">');
    _ctx.writeMeter(
      body,
      'Lines',
      record.linesHit,
      record.linesFound,
      lPct,
      threshold: _ctx.limits.line,
    );
    _ctx.writeMeter(
      body,
      'Branches',
      record.branchesHit,
      record.branchesFound,
      bPct,
      threshold: _ctx.limits.branch,
    );
    _ctx.writeMeter(
      body,
      'Functions',
      record.functionsHit,
      record.functionsFound,
      fPct,
      threshold: _ctx.limits.function,
    );
    body.writeln('</div>');
    body.writeln('</div>');

    body.writeln('<div class="source">');
    body.writeln('<table>');
    body.writeln(
      '<colgroup>'
      '<col class="col-line">'
      '<col class="col-hits">'
      '<col class="col-branch">'
      '<col class="col-source">'
      '</colgroup>',
    );
    body.writeln(
      '<thead><tr>'
      '<th class="col-header">line</th>'
      '<th class="col-header">hits</th>'
      '<th class="col-header">branches</th>'
      '<th></th>'
      '</tr></thead>',
    );

    for (var i = 0; i < sourceLines.length; i++) {
      final lineNum = i + 1;
      final hits = lineHits[lineNum];
      final branches = branchLines[lineNum] ?? [];
      final takenBranches = branches.where((b) => (b.hits ?? 0) > 0).length;
      final branchStr = branches.isEmpty
          ? ''
          : '$takenBranches/${branches.length}';

      body.write('<tr class="${_ctx.lineClass(hits, branches)}">');
      body.write('<td class="line-num">$lineNum</td>');
      body.write('<td class="stat">${hits ?? ''}</td>');
      body.write('<td class="stat">$branchStr</td>');
      body.write(
        '<td class="src"><pre>${_ctx.escape(sourceLines[i])}</pre></td>',
      );
      body.writeln('</tr>');
    }

    body.writeln('</table>');
    body.writeln('</div>');

    await pageFile.writeAsString(_ctx.render(headerPath, body.toString()));
    return pageFile.path;
  }
}
