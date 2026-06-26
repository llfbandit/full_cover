import 'lcov_record.dart';

class LcovMerger {
  List<LcovRecord> merge(List<List<LcovRecord>> packageRecords) {
    final byFile = <String, LcovRecord>{};

    for (final records in packageRecords) {
      for (final record in records) {
        final existing = byFile[record.sourceFile];
        byFile[record.sourceFile] = existing == null
            ? record
            : _mergeTwo(existing, record);
      }
    }

    return byFile.values.toList();
  }

  LcovRecord _mergeTwo(LcovRecord a, LcovRecord b) {
    // Lines: sum hit counts per line number
    final lineMap = <int, int>{};
    for (final l in a.lines) {
      lineMap[l.line] = (lineMap[l.line] ?? 0) + l.hits;
    }
    for (final l in b.lines) {
      lineMap[l.line] = (lineMap[l.line] ?? 0) + l.hits;
    }
    final lines = lineMap.entries.map((e) => LineData(e.key, e.value)).toList()
      ..sort((x, y) => x.line.compareTo(y.line));

    // Branches: sum hit counts per (line, block, branch) key
    final branchMap = <String, ({int line, int block, int branch, int hits})>{};
    for (final br in [...a.branches, ...b.branches]) {
      final key = '${br.line},${br.block},${br.branch}';
      final prev = branchMap[key];
      branchMap[key] = (
        line: br.line,
        block: br.block,
        branch: br.branch,
        hits: (prev?.hits ?? 0) + (br.hits ?? 0),
      );
    }
    final branches =
        branchMap.values
            .map((e) => BranchData(e.line, e.block, e.branch, e.hits))
            .toList()
          ..sort((x, y) => x.line.compareTo(y.line));

    // Functions: sum hit counts per name
    final fnMap = <String, FunctionData>{};
    for (final fn in [...a.functions, ...b.functions]) {
      final prev = fnMap[fn.name];
      if (prev == null) {
        fnMap[fn.name] = FunctionData(fn.name, fn.line, hits: fn.hits);
      } else {
        prev.hits += fn.hits;
      }
    }
    final functions = fnMap.values.toList()
      ..sort((x, y) => x.line.compareTo(y.line));

    return LcovRecord(
      sourceFile: a.sourceFile,
      functions: functions,
      branches: branches,
      lines: lines,
    );
  }
}
