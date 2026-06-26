import 'package:path/path.dart' as p;

import '../config/limits_config.dart';
import '../coverage/lcov_record.dart';

class HtmlRenderContext {
  final LimitsConfig limits;
  final String _pageTemplate;

  HtmlRenderContext({required this.limits, required String pageTemplate})
    : _pageTemplate = pageTemplate;

  // ----------------------------------------------------------------- escaping

  String escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String pct(double v) => '${v.toStringAsFixed(1)}%';

  // -------------------------------------------------------- coverage colouring

  String coverageClass(double value, ThresholdConfig? threshold) {
    final t = threshold ?? const ThresholdConfig();
    if (value >= t.effectiveAverage) return 'high';
    if (value >= t.effectiveMinimum) return 'medium';
    return 'low';
  }

  String cellClass(double value, ThresholdConfig? threshold) =>
      'cov-${coverageClass(value, threshold)}';

  String lineClass(int? hits, List<BranchData> branches) {
    if (hits == null) return 'neutral';
    if (hits == 0) return 'miss';
    if (branches.isNotEmpty && branches.any((b) => (b.hits ?? 0) == 0)) {
      return 'partial';
    }
    return 'hit';
  }

  // ------------------------------------------------------------------ widgets

  void writeMeter(
    StringBuffer buf,
    String label,
    int hit,
    int total,
    double value, {
    ThresholdConfig? threshold,
  }) {
    final cls = coverageClass(value, threshold);
    buf.write('<div class="meter $cls">');
    buf.write('<span class="meter-label">$label</span>');
    buf.write('<span class="meter-value">${pct(value)}</span>');
    buf.write('<span class="meter-count">$hit/$total</span>');
    if (threshold?.minimum != null) {
      final met = value >= threshold!.minimum!;
      buf.write(
        '<span class="threshold-chip ${met ? 'threshold-pass' : 'threshold-fail'}">'
        'min ${pct(threshold.minimum!)}</span>',
      );
    }
    if (threshold?.average != null) {
      final met = value >= threshold!.average!;
      buf.write(
        '<span class="threshold-chip ${met ? 'threshold-pass' : 'threshold-fail'}">'
        'avg ${pct(threshold.average!)}</span>',
      );
    }
    buf.writeln('</div>');
  }

  void emitFolderHeaderRow(
    StringBuffer buf,
    String displayName,
    List<LcovRecord> records,
    String pkgName,
    String href,
    bool hasTree,
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
    final groupAttr = pkgName.isNotEmpty
        ? ' data-group="${escape(pkgName)}"'
        : '';
    final cellIndent = hasTree ? ' class="file-cell"' : '';

    buf.write('<tr class="folder-header"$groupAttr>');
    buf.write(
      '<td$cellIndent><a class="folder-link" href="${escape(href)}">${escape(displayName)}/</a></td>',
    );
    buf.write(
      '<td class="${cellClass(lPct, limits.line)}" data-value="$lPct">${pct(lPct)} <span class="count">$lH/$lF</span></td>',
    );
    buf.write(
      '<td class="${cellClass(bPct, limits.branch)}" data-value="$bPct">${pct(bPct)} <span class="count">$bH/$bF</span></td>',
    );
    buf.write(
      '<td class="${cellClass(fPct, limits.function)}" data-value="$fPct">${pct(fPct)} <span class="count">$fH/$fF</span></td>',
    );
    buf.writeln('</tr>');
  }

  void emitFileRow(
    StringBuffer buf,
    LcovRecord record,
    String pkgName,
    String? folderPrefix,
    Map<LcovRecord, String> filePagePaths,
    String fromDir,
    bool hasTree,
  ) {
    final split = splitByPackage(record.sourceFile);
    final lPct = record.linesFound == 0
        ? 100.0
        : record.linesHit / record.linesFound * 100;
    final bPct = record.branchesFound == 0
        ? 100.0
        : record.branchesHit / record.branchesFound * 100;
    final fPct = record.functionsFound == 0
        ? 100.0
        : record.functionsHit / record.functionsFound * 100;
    final displayName = folderPrefix != null
        ? split.shortPath.substring(folderPrefix.length + 1)
        : split.shortPath;
    final pageRelPath = p
        .relative(filePagePaths[record]!, from: fromDir)
        .replaceAll(r'\', '/');
    final groupAttr = pkgName.isNotEmpty
        ? ' data-group="${escape(pkgName)}"'
        : '';
    final cellIndent = hasTree ? ' class="file-cell"' : '';

    buf.write('<tr$groupAttr>');
    buf.write(
      '<td$cellIndent><a class="file-link" href="${escape(pageRelPath)}">${escape(displayName)}</a></td>',
    );
    buf.write(
      '<td class="${cellClass(lPct, limits.line)}" data-value="$lPct">${pct(lPct)} <span class="count">${record.linesHit}/${record.linesFound}</span></td>',
    );
    buf.write(
      '<td class="${cellClass(bPct, limits.branch)}" data-value="$bPct">${pct(bPct)} <span class="count">${record.branchesHit}/${record.branchesFound}</span></td>',
    );
    buf.write(
      '<td class="${cellClass(fPct, limits.function)}" data-value="$fPct">${pct(fPct)} <span class="count">${record.functionsHit}/${record.functionsFound}</span></td>',
    );
    buf.writeln('</tr>');
  }

  // ------------------------------------------------------------------- paths

  ({String package, String shortPath}) splitByPackage(String sourceFile) {
    final norm = sourceFile.replaceAll(r'\', '/');
    final libIdx = norm.indexOf('/lib/');
    if (libIdx < 0) return (package: '', shortPath: p.basename(sourceFile));
    final packageName = norm.substring(0, libIdx).split('/').last;
    var rel = norm.substring(libIdx + '/lib/'.length);
    if (rel.startsWith('src/')) rel = rel.substring('src/'.length);
    return (package: packageName, shortPath: rel);
  }

  String displayPath(String sourceFile, String? rootPath) {
    if (rootPath == null) return sourceFile;
    final absRoot = p.normalize(p.absolute(rootPath));
    final absFile = p.normalize(
      p.isAbsolute(sourceFile) ? sourceFile : p.absolute(sourceFile),
    );
    if (absFile.startsWith(absRoot)) return p.relative(absFile, from: absRoot);
    return sourceFile;
  }

  String folderPageName(String pkgName, String folderPath) {
    final safe = '${pkgName}_$folderPath'.replaceAll(
      RegExp(r'[/\\:*?"<>|]'),
      '_',
    );
    return '_dir_$safe.html';
  }

  // ---------------------------------------------------------------- template

  String render(String title, String body, {String assetsPrefix = ''}) {
    return _pageTemplate
        .replaceFirst('{{title}}', escape(title))
        .replaceAll('{{assets_prefix}}', assetsPrefix)
        .replaceFirst('{{body}}', body);
  }
}
