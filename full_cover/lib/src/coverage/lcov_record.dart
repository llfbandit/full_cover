class LineData {
  final int line;
  final int hits;
  const LineData(this.line, this.hits);
}

class BranchData {
  final int line;
  final int block;
  final int branch;
  final int? hits; // null means '-' (not executed path)
  const BranchData(this.line, this.block, this.branch, this.hits);
}

class FunctionData {
  final String name;
  final int line;
  int hits;
  FunctionData(this.name, this.line, {this.hits = 0});
}

class LcovRecord {
  final String sourceFile;
  final List<FunctionData> functions;
  final List<BranchData> branches;
  final List<LineData> lines;

  const LcovRecord({
    required this.sourceFile,
    this.functions = const [],
    this.branches = const [],
    this.lines = const [],
  });

  int get linesFound => lines.length;
  int get linesHit => lines.where((l) => l.hits > 0).length;
  int get branchesFound => branches.length;
  int get branchesHit => branches.where((b) => (b.hits ?? 0) > 0).length;
  int get functionsFound => functions.length;
  int get functionsHit => functions.where((f) => f.hits > 0).length;

  double get lineCoverage => linesFound == 0 ? 1.0 : linesHit / linesFound;
  double get branchCoverage =>
      branchesFound == 0 ? 1.0 : branchesHit / branchesFound;

  LcovRecord copyWith({
    String? sourceFile,
    List<FunctionData>? functions,
    List<BranchData>? branches,
    List<LineData>? lines,
  }) {
    return LcovRecord(
      sourceFile: sourceFile ?? this.sourceFile,
      functions: functions ?? this.functions,
      branches: branches ?? this.branches,
      lines: lines ?? this.lines,
    );
  }

  String toInfoString() {
    final buf = StringBuffer();
    buf.writeln('SF:$sourceFile');
    for (final fn in functions) {
      buf.writeln('FN:${fn.line},${fn.name}');
    }
    for (final fn in functions) {
      buf.writeln('FNDA:${fn.hits},${fn.name}');
    }
    buf.writeln('FNF:${functions.length}');
    buf.writeln('FNH:${functions.where((f) => f.hits > 0).length}');
    for (final br in branches) {
      final hitStr = br.hits == null ? '-' : '${br.hits}';
      buf.writeln('BRDA:${br.line},${br.block},${br.branch},$hitStr');
    }
    buf.writeln('BRF:${branches.length}');
    buf.writeln('BRH:${branches.where((b) => (b.hits ?? 0) > 0).length}');
    for (final ln in lines) {
      buf.writeln('DA:${ln.line},${ln.hits}');
    }
    buf.writeln('LF:${lines.length}');
    buf.writeln('LH:${lines.where((l) => l.hits > 0).length}');
    buf.write('end_of_record');
    return buf.toString();
  }
}
