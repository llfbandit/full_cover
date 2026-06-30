import 'dart:io';

import 'package:full_cover/src/coverage/branch_analyzer.dart';
import 'package:full_cover/src/coverage/lcov_record.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('fc_ba_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  File writeSource(String name, String content) =>
      File(p.join(tempDir.path, name))..writeAsStringSync(content);

  LcovRecord record(String path, Map<int, int> hits) => LcovRecord(
    sourceFile: path,
    lines: hits.entries.map((e) => LineData(e.key, e.value)).toList(),
  );

  final analyzer = BranchAnalyzer();

  test('returns record unchanged when file does not exist', () {
    final r = record('/no/such/file.dart', {});
    expect(analyzer.analyze(r).sourceFile, r.sourceFile);
    expect(analyzer.analyze(r).branches, isEmpty);
  });

  test('extracts function from function declaration', () {
    final file = writeSource('fn.dart', '''
int add(int a, int b) {
  return a + b;
}
''');
    final result = analyzer.analyze(record(file.path, {1: 5, 2: 5}));
    expect(result.functionsFound, 1);
    expect(result.functions.first.name, 'add');
    expect(result.functions.first.hits, 5);
  });

  test('function hit count falls back to the declaration line', () {
    final file = writeSource('switch_fn.dart', '''
void run(int n) {
  switch (n) {
    case 1:
      print('one');
  }
}
''');
    // The VM omits the bare `switch` line (2), but records the declaration
    // line (1). The function must still read as reached.
    final result = analyzer.analyze(record(file.path, {1: 1, 3: 1, 4: 1}));
    expect(result.functions.single.name, 'run');
    expect(result.functions.single.hits, 1);
  });

  test('function with a constant-return first statement reads as reached', () {
    final file = writeSource('const_return_fn.dart', '''
String f() {
  return 'x';
}
''');
    // The VM omits the constant-return line (2) but records the decl line (1).
    final result = analyzer.analyze(record(file.path, {1: 1}));
    expect(result.functions.single.hits, 1);
  });

  test('extracts method from class declaration', () {
    final file = writeSource('cls.dart', '''
class Foo {
  int value() {
    return 42;
  }
}
''');
    final result = analyzer.analyze(record(file.path, {2: 3, 3: 3}));
    expect(result.functionsFound, 1);
    expect(result.functions.first.name, 'Foo.value');
  });

  test('extracts constructors and skips redirecting ones', () {
    final file = writeSource('ctor.dart', '''
class Point {
  final int x;
  Point(this.x) {
    print(x);
  }
  Point.origin() {
    print('origin');
  }
  Point.zero() : this(0);
}
''');
    final result = analyzer.analyze(
      record(file.path, {1: 1, 3: 2, 4: 2, 6: 1, 7: 1}),
    );

    final byName = {for (final f in result.functions) f.name: f};
    expect(byName['Point']?.hits, 2); // unnamed ctor → bare type name
    expect(byName['Point.origin']?.hits, 1); // named ctor → Type.name
    expect(byName.containsKey('Point.zero'), isFalse); // redirecting → skipped
  });

  test('extracts branches from multi-line if', () {
    final file = writeSource('if.dart', '''
void check(bool x) {
  if (x) {
    print('yes');
  } else {
    print('no');
  }
}
''');
    final result = analyzer.analyze(
      record(file.path, {1: 4, 2: 4, 3: 3, 4: 3, 5: 1, 6: 1, 7: 4}),
    );
    expect(result.branchesFound, 2);
    expect(result.branches[0].hits, 3); // then taken 3 times
    expect(result.branches[1].hits, 1); // else taken once
  });

  test('infers false arm of a multi-line if with an empty else block', () {
    final file = writeSource('empty_else.dart', '''
void f(bool x) {
  if (x) {
    print('yes');
  } else {}
}
''');
    // Then-body is on line 3 (multi-line), else block is empty so it has no
    // body line — the false arm is inferred as condHits - trueHits.
    final result = analyzer.analyze(record(file.path, {1: 1, 2: 3, 3: 2}));

    final ifArms = result.branches.where((b) => b.line == 2).toList();
    expect(ifArms, hasLength(2));
    expect(ifArms[0].hits, 2); // then = hits at line 3
    expect(ifArms[1].hits, 1); // else = condHits(3) - trueHits(2)
  });

  test('skips a single-line if-else (arms not inferable)', () {
    final file = writeSource('single_if_else.dart', '''
bool f(bool x) {
  if (x) return true; else return false;
}
''');
    // Both arms share the decision line; neither can be read from line hits.
    final result = analyzer.analyze(record(file.path, {1: 1, 2: 2}));
    expect(result.branchesFound, 0);
  });

  test('handles a single-line if with no fall-through sibling', () {
    final file = writeSource('single_if_last.dart', '''
void f(bool x) {
  if (x) return;
}
''');
    // The if is the last statement in its block, so there is no sibling to
    // infer the false arm from — only the true arm is recorded.
    final result = analyzer.analyze(record(file.path, {1: 1, 2: 2}));
    expect(result.branches, hasLength(1));
    expect(result.branches.single.branch, 0);
  });

  test('extracts branches from a collection if/else element', () {
    final file = writeSource('collection_if.dart', '''
List<String> f(bool x) {
  return [
    if (x)
      'yes'
    else
      'no',
  ];
}
''');
    // `if` used as a collection element (inside the list literal) is an
    // IfElement, not an IfStatement.
    final result = analyzer.analyze(
      record(file.path, {1: 2, 2: 2, 3: 2, 4: 1, 6: 1}),
    );

    final arms = result.branches.where((b) => b.line == 3).toList();
    expect(arms, hasLength(2));
    expect(arms[0].hits, 1); // then 'yes' at line 4
    expect(arms[1].hits, 1); // else 'no' at line 6
  });

  test('extracts branches from ternary on separate lines', () {
    final file = writeSource('ternary.dart', '''
String label(bool x) => x
    ? 'yes'
    : 'no';
''');
    final result = analyzer.analyze(record(file.path, {1: 5, 2: 3, 3: 2}));
    expect(result.branchesFound, 2);
    expect(result.branches[0].hits, 3);
    expect(result.branches[1].hits, 2);
  });

  test('extracts branches from switch statement', () {
    final file = writeSource('sw.dart', '''
String describe(int n) {
  switch (n) {
    case 1:
      return 'one';
    case 2:
      return 'two';
    default:
      return 'other';
  }
}
''');
    final result = analyzer.analyze(
      record(file.path, {1: 6, 2: 6, 4: 2, 6: 3, 8: 1}),
    );
    expect(result.branchesFound, 3); // case 1, case 2, default
  });

  test('infers single-line if fall-through inside a switch case', () {
    final file = writeSource('switch_if.dart', '''
void f(int n) {
  switch (n) {
    case 1:
      if (n > 0) return;
      print('after');
  }
}
''');
    // The single-line `if` at line 4 sits directly in the switch case (no
    // braces), so its fall-through sibling is found via the SwitchMember path.
    final result = analyzer.analyze(
      record(file.path, {1: 1, 2: 1, 3: 1, 4: 2, 5: 1}),
    );

    final ifArms = result.branches.where((b) => b.line == 4).toList();
    expect(ifArms, hasLength(2));
    expect(ifArms[1].hits, 1); // false arm = fall-through hits at line 5
  });

  test('no branches for a file with no decision points', () {
    final file = writeSource('simple.dart', '''
int square(int x) {
  return x * x;
}
''');
    final result = analyzer.analyze(record(file.path, {1: 1, 2: 1}));
    expect(result.branchesFound, 0);
    expect(result.functionsFound, 1);
  });

  test('backfills VM-omitted fall-through statement lines as uncovered', () {
    final file = writeSource('threshold.dart', '''
String summary(bool passes, bool a, bool b) {
  if (passes) return 'met';
  if (a && b) {
    return 'both';
  }
  if (a) return 'line';
  return 'branch';
}
''');
    // The VM omits line 4 (multi-line if body) and line 7 (fall-through return)
    // — they are never reached and the VM emits no position for them.
    final result = analyzer.analyze(
      record(file.path, {1: 3, 2: 3, 3: 2, 6: 2}),
    );

    final byLine = {for (final l in result.lines) l.line: l.hits};
    expect(byLine[4], 0, reason: 'multi-line if body should be flagged');
    expect(byLine[7], 0, reason: 'fall-through return should be flagged');
  });

  test('uses VM branch data when the arm body line is omitted', () {
    final file = writeSource('vmbranch.dart', '''
bool f(bool x) {
  if (x) {
    return true;
  } else {
    return false;
  }
}
''');
    // The VM omits the constant-return body lines (3, 5) from line data, but
    // records both arms as taken via BRDA at their entry lines (2 = then/if,
    // 4 = else). The analyzer must trust the branch data over the line gap.
    final rec = LcovRecord(
      sourceFile: file.path,
      lines: const [LineData(1, 1), LineData(2, 1), LineData(4, 1)],
      branches: const [BranchData(2, 0, 0, 1), BranchData(4, 0, 0, 1)],
    );

    final result = analyzer.analyze(rec);
    expect(result.branchesFound, 2);
    expect(
      result.branches.every((b) => (b.hits ?? 0) > 0),
      isTrue,
      reason: 'both arms should be reported as taken',
    );

    // And the omitted body lines are backfilled as covered, not flagged red.
    final byLine = {for (final l in result.lines) l.line: l.hits};
    expect(byLine[3], greaterThan(0));
    expect(byLine[5], greaterThan(0));
  });

  test('keeps the max when multiple VM branches share a line', () {
    final file = writeSource('shared_line_branch.dart', '''
bool f(bool x) {
  if (x) return true;
  return false;
}
''');
    // Three BRDA entries on line 2 — the merge keeps the highest hit count,
    // exercising both outcomes of the max (3 > 1, then 2 < 3).
    final rec = LcovRecord(
      sourceFile: file.path,
      lines: const [LineData(1, 1), LineData(2, 5)],
      branches: const [
        BranchData(2, 0, 0, 1),
        BranchData(2, 0, 1, 3),
        BranchData(2, 0, 2, 2),
      ],
    );

    final result = analyzer.analyze(rec);
    final trueArm = result.branches.firstWhere(
      (b) => b.line == 2 && b.branch == 0,
    );
    expect(trueArm.hits, 3); // max(1, 3, 2)
  });

  test('strips abstract method declaration lines from line coverage', () {
    final file = writeSource('abstract_method.dart', '''
abstract class Shape {
  double area();
}
''');
    // The VM may emit a coverable position for the abstract declaration (line 2).
    // It must be removed — there is no executable body to cover.
    final result = analyzer.analyze(record(file.path, {2: 1}));
    final lines = {for (final l in result.lines) l.line};
    expect(lines, isNot(contains(2)));
    expect(result.functionsFound, 0);
  });

  test('strips abstract lines but keeps concrete ones in the same class', () {
    final file = writeSource('mixed_abstract.dart', '''
abstract class Shape {
  double area();
  String name() {
    return 'shape';
  }
}
''');
    final result = analyzer.analyze(record(file.path, {2: 1, 3: 2, 4: 2}));
    final byLine = {for (final l in result.lines) l.line: l.hits};
    expect(byLine.containsKey(2), isFalse, reason: 'abstract decl stripped');
    expect(byLine[3], 2);
    expect(byLine[4], 2);
    expect(result.functionsFound, 1); // only the concrete method
    expect(result.functions.single.name, 'Shape.name');
  });

  test('strips all lines of a multi-line abstract declaration', () {
    final file = writeSource('multiline_abstract.dart', '''
abstract class Foo {
  Map<String, dynamic>
      toJson();
}
''');
    final result = analyzer.analyze(record(file.path, {2: 1, 3: 1}));
    final lines = {for (final l in result.lines) l.line};
    expect(lines, isNot(contains(2)));
    expect(lines, isNot(contains(3)));
  });

  test('fully-abstract file produces an empty record (no lines/functions/branches)', () {
    final file = writeSource('all_abstract.dart', '''
abstract class Repository {
  Future<List<String>> fetchAll();
  Future<void> save(String item);
  int get count;
}
''');
    // Every member is abstract — after stripping, the record must be empty so
    // the runner can drop it rather than reporting it as 100% covered.
    final result = analyzer.analyze(record(file.path, {2: 1, 3: 1, 4: 1}));
    expect(result.lines, isEmpty);
    expect(result.functions, isEmpty);
    expect(result.branches, isEmpty);
  });

  test('strips abstract getter declaration lines', () {
    final file = writeSource('abstract_getter.dart', '''
abstract class Foo {
  int get value;
  set value(int v);
}
''');
    final result = analyzer.analyze(record(file.path, {2: 1, 3: 1}));
    final lines = {for (final l in result.lines) l.line};
    expect(lines, isNot(contains(2)));
    expect(lines, isNot(contains(3)));
  });

  test('does not override existing VM line hits when backfilling', () {
    final file = writeSource('present.dart', '''
String summary(bool a) {
  if (a) return 'x';
  return 'y';
}
''');
    // Line 3 is present with real VM hits and must be preserved as-is.
    final result = analyzer.analyze(record(file.path, {1: 5, 2: 5, 3: 2}));

    final byLine = {for (final l in result.lines) l.line: l.hits};
    expect(byLine[3], 2);
  });
}
