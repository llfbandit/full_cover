import 'package:full_cover/src/coverage/lcov_parser.dart';
import 'package:test/test.dart';

void main() {
  final parser = LcovParser();

  const minimal = '''
SF:lib/src/foo.dart
DA:1,1
DA:2,0
LF:2
LH:1
end_of_record
''';

  test('parses source file and line data', () {
    final records = parser.parse(minimal);
    expect(records, hasLength(1));
    final r = records.first;
    expect(r.sourceFile, 'lib/src/foo.dart');
    expect(r.linesFound, 2);
    expect(r.linesHit, 1);
  });

  test('parses function data', () {
    const content = '''
SF:lib/a.dart
FN:10,myFn
FNDA:3,myFn
FNF:1
FNH:1
end_of_record
''';
    final r = parser.parse(content).first;
    expect(r.functionsFound, 1);
    expect(r.functionsHit, 1);
    expect(r.functions.first.hits, 3);
    expect(r.functions.first.line, 10);
  });

  test('parses branch data with dash hit as null', () {
    const content = '''
SF:lib/a.dart
BRDA:5,0,0,2
BRDA:5,0,1,-
BRF:2
BRH:1
end_of_record
''';
    final r = parser.parse(content).first;
    expect(r.branchesFound, 2);
    expect(r.branchesHit, 1);
    expect(r.branches[1].hits, isNull);
  });

  test('parses multiple records', () {
    const content = '''
SF:lib/a.dart
DA:1,1
end_of_record
SF:lib/b.dart
DA:1,0
end_of_record
''';
    final records = parser.parse(content);
    expect(records, hasLength(2));
    expect(records[0].sourceFile, 'lib/a.dart');
    expect(records[1].sourceFile, 'lib/b.dart');
  });

  test('skips records with no SF', () {
    const content = '''
DA:1,1
end_of_record
''';
    expect(parser.parse(content), isEmpty);
  });

  test('ignores unknown tags', () {
    const content = '''
SF:lib/a.dart
TN:some_test_name
DA:1,5
end_of_record
''';
    final r = parser.parse(content).first;
    expect(r.linesFound, 1);
  });

  test('round-trips via toInfoString', () {
    final original = parser.parse(minimal).first;
    final roundTripped = parser.parse(original.toInfoString()).first;
    expect(roundTripped.sourceFile, original.sourceFile);
    expect(roundTripped.linesFound, original.linesFound);
    expect(roundTripped.linesHit, original.linesHit);
  });
}
