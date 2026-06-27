import 'package:full_cover/src/coverage/lcov_filter.dart';
import 'package:full_cover/src/coverage/lcov_record.dart';
import 'package:test/test.dart';

LcovRecord _rec(String sf) => LcovRecord(sourceFile: sf);

void main() {
  final filter = LcovFilter();

  test('returns all records when patterns is empty', () {
    final records = [_rec('lib/a.dart'), _rec('lib/b.dart')];
    expect(filter.apply(records: records, filePatterns: []), records);
  });

  test('excludes files matching glob pattern', () {
    final records = [_rec('lib/src/foo.g.dart'), _rec('lib/src/bar.dart')];
    final result = filter.apply(
      records: records,
      filePatterns: ['**/*.g.dart'],
    );
    expect(result, hasLength(1));
    expect(result.first.sourceFile, 'lib/src/bar.dart');
  });

  test('excludes by relative path when packagePath provided', () {
    final records = [
      _rec('lib/src/generated/foo.dart'),
      _rec('lib/src/real.dart'),
    ];
    final result = filter.apply(
      records: records,
      filePatterns: ['lib/src/generated/**'],
      packagePath: '.',
    );
    expect(result, hasLength(1));
    expect(result.first.sourceFile, 'lib/src/real.dart');
  });

  test('multiple patterns: any match excludes the record', () {
    final records = [
      _rec('lib/a.freezed.dart'),
      _rec('lib/b.g.dart'),
      _rec('lib/c.dart'),
    ];
    final result = filter.apply(
      records: records,
      filePatterns: ['**/*.freezed.dart', '**/*.g.dart'],
    );
    expect(result, hasLength(1));
    expect(result.first.sourceFile, 'lib/c.dart');
  });
}
