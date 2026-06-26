import 'lcov_record.dart';

class LcovParser {
  List<LcovRecord> parse(String content) {
    final records = <LcovRecord>[];

    String? currentFile;
    final functions = <FunctionData>[];
    final branches = <BranchData>[];
    final lines = <LineData>[];
    final fnHits = <String, int>{};

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line == 'end_of_record') {
        if (currentFile != null) {
          for (final fn in functions) {
            fn.hits = fnHits[fn.name] ?? 0;
          }
          records.add(
            LcovRecord(
              sourceFile: currentFile,
              functions: List.of(functions),
              branches: List.of(branches),
              lines: List.of(lines),
            ),
          );
        }
        currentFile = null;
        functions.clear();
        branches.clear();
        lines.clear();
        fnHits.clear();
        continue;
      }

      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final tag = line.substring(0, colonIdx);
      final value = line.substring(colonIdx + 1);

      switch (tag) {
        case 'SF':
          currentFile = value;
        case 'FN':
          final commaIdx = value.indexOf(',');
          if (commaIdx >= 0) {
            final lineNum = int.tryParse(value.substring(0, commaIdx)) ?? 0;
            final name = value.substring(commaIdx + 1);
            functions.add(FunctionData(name, lineNum));
          }
        case 'FNDA':
          final commaIdx = value.indexOf(',');
          if (commaIdx >= 0) {
            final hits = int.tryParse(value.substring(0, commaIdx)) ?? 0;
            final name = value.substring(commaIdx + 1);
            fnHits[name] = hits;
          }
        case 'BRDA':
          final parts = value.split(',');
          if (parts.length >= 4) {
            final lineNum = int.tryParse(parts[0]) ?? 0;
            final block = int.tryParse(parts[1]) ?? 0;
            final branch = int.tryParse(parts[2]) ?? 0;
            final hitStr = parts[3];
            final hits = hitStr == '-' ? null : int.tryParse(hitStr);
            branches.add(BranchData(lineNum, block, branch, hits));
          }
        case 'DA':
          final commaIdx = value.indexOf(',');
          if (commaIdx >= 0) {
            final lineNum = int.tryParse(value.substring(0, commaIdx)) ?? 0;
            final hits = int.tryParse(value.substring(commaIdx + 1)) ?? 0;
            lines.add(LineData(lineNum, hits));
          }
        default:
          break; // TN, FNF, FNH, BRF, BRH, LF, LH are computed, skip
      }
    }

    return records;
  }
}
