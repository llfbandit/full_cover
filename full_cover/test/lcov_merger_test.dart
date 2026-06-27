import 'package:full_cover/src/coverage/lcov_merger.dart';
import 'package:full_cover/src/coverage/lcov_record.dart';
import 'package:test/test.dart';

void main() {
  final merger = LcovMerger();

  test('flattens non-overlapping records', () {
    final a = LcovRecord(sourceFile: 'lib/a.dart', lines: [LineData(1, 1)]);
    final b = LcovRecord(sourceFile: 'lib/b.dart', lines: [LineData(1, 2)]);
    final result = merger.merge([
      [a],
      [b],
    ]);
    expect(result, hasLength(2));
  });

  test('merges overlapping records by summing line hits', () {
    final a = LcovRecord(
      sourceFile: 'lib/a.dart',
      lines: [LineData(1, 2), LineData(2, 0)],
    );
    final b = LcovRecord(
      sourceFile: 'lib/a.dart',
      lines: [LineData(1, 3), LineData(2, 1)],
    );
    final result = merger.merge([
      [a],
      [b],
    ]);
    expect(result, hasLength(1));
    final r = result.first;
    expect(r.lines.firstWhere((l) => l.line == 1).hits, 5);
    expect(r.lines.firstWhere((l) => l.line == 2).hits, 1);
  });

  test('merges branch hits', () {
    final a = LcovRecord(
      sourceFile: 'lib/a.dart',
      branches: [BranchData(5, 0, 0, 1), BranchData(5, 0, 1, 0)],
    );
    final b = LcovRecord(
      sourceFile: 'lib/a.dart',
      branches: [BranchData(5, 0, 0, 2), BranchData(5, 0, 1, 1)],
    );
    final result = merger.merge([
      [a],
      [b],
    ]);
    final r = result.first;
    expect(r.branches.firstWhere((b) => b.branch == 0).hits, 3);
    expect(r.branches.firstWhere((b) => b.branch == 1).hits, 1);
  });

  test('merges function hits', () {
    final a = LcovRecord(
      sourceFile: 'lib/a.dart',
      functions: [FunctionData('myFn', 1, hits: 1)],
    );
    final b = LcovRecord(
      sourceFile: 'lib/a.dart',
      functions: [FunctionData('myFn', 1, hits: 4)],
    );
    final result = merger.merge([
      [a],
      [b],
    ]);
    expect(result.first.functions.first.hits, 5);
  });

  test('handles empty input', () {
    expect(merger.merge([]), isEmpty);
    expect(merger.merge([[]]), isEmpty);
  });
}
