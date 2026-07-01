import 'dart:io';

import 'package:full_cover/src/coverage/lcov_filter.dart';
import 'package:full_cover/src/coverage/lcov_record.dart';
import 'package:path/path.dart' as p;
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

  group('negation patterns', () {
    test('! re-includes a file excluded by a prior pattern', () {
      final records = [
        _rec('lib/ui/widget.dart'),
        _rec('lib/ui/my_bloc.dart'),
        _rec('lib/other.dart'),
      ];
      final result = filter.apply(
        records: records,
        filePatterns: ['lib/ui/**', '!lib/ui/**_bloc.dart'],
      );
      expect(
        result.map((r) => r.sourceFile),
        containsAll(['lib/ui/my_bloc.dart', 'lib/other.dart']),
      );
      expect(
        result.map((r) => r.sourceFile),
        isNot(contains('lib/ui/widget.dart')),
      );
    });

    test('! after a matching pattern wins (last match wins)', () {
      final records = [_rec('lib/src/foo.g.dart')];
      final result = filter.apply(
        records: records,
        filePatterns: ['**/*.g.dart', '!lib/src/foo.g.dart'],
      );
      expect(result, hasLength(1));
    });

    test('exclude after ! re-excludes', () {
      final records = [_rec('lib/ui/my_bloc.dart')];
      final result = filter.apply(
        records: records,
        filePatterns: [
          'lib/ui/**',
          '!lib/ui/**_bloc.dart',
          'lib/ui/my_bloc.dart',
        ],
      );
      expect(result, isEmpty);
    });

    test('standalone ! with no prior match keeps file', () {
      final records = [_rec('lib/a.dart')];
      final result = filter.apply(
        records: records,
        filePatterns: ['!lib/b.dart'],
      );
      expect(result, hasLength(1));
    });
  });

  group('filterSiblingExcludes', () {
    late Directory base;
    late String pkgA;
    late String pkgB;

    setUp(() {
      base = Directory.systemTemp.createTempSync('fc_filter_');
      pkgA = p.join(base.path, 'pkg_a');
      pkgB = p.join(base.path, 'pkg_b');
    });
    tearDown(() => base.deleteSync(recursive: true));

    List<SiblingPattern> patterns(
      List<({String path, List<String> excludes})> siblings, {
      List<String> globalExcludes = const [],
    }) => LcovFilter.prepareSiblingPatterns(
      siblings: siblings,
      globalExcludes: globalExcludes,
    );

    test('passes through own-package records regardless of siblings', () {
      final records = [_rec(p.join(pkgA, 'lib', 'a.dart'))];
      final result = LcovFilter.filterSiblingExcludes(
        records: records,
        currentPkgPath: pkgA,
        siblingPatterns: patterns([
          (path: pkgB, excludes: ['**']),
        ]),
      );
      expect(result, hasLength(1));
    });

    test('keeps sibling record when no exclusions apply', () {
      final records = [
        _rec(p.join(pkgA, 'lib', 'a.dart')),
        _rec(p.join(pkgB, 'lib', 'b.dart')),
      ];
      final result = LcovFilter.filterSiblingExcludes(
        records: records,
        currentPkgPath: pkgA,
        siblingPatterns: patterns([(path: pkgB, excludes: [])]),
      );
      expect(result, hasLength(2));
    });

    test('removes sibling record matched by sibling package_excludes', () {
      final records = [
        _rec(p.join(pkgA, 'lib', 'a.dart')),
        _rec(p.join(pkgB, 'lib', 'gen', 'b.g.dart')),
        _rec(p.join(pkgB, 'lib', 'real.dart')),
      ];
      final result = LcovFilter.filterSiblingExcludes(
        records: records,
        currentPkgPath: pkgA,
        siblingPatterns: patterns([
          (path: pkgB, excludes: ['lib/gen/**']),
        ]),
      );
      final files = result.map((r) => r.sourceFile).toList();
      expect(files, contains(p.join(pkgA, 'lib', 'a.dart')));
      expect(files, contains(p.join(pkgB, 'lib', 'real.dart')));
      expect(files, isNot(contains(p.join(pkgB, 'lib', 'gen', 'b.g.dart'))));
    });

    test('removes sibling record matched by global_excludes', () {
      final records = [
        _rec(p.join(pkgA, 'lib', 'a.dart')),
        _rec(p.join(pkgB, 'lib', 'b.g.dart')),
      ];
      final result = LcovFilter.filterSiblingExcludes(
        records: records,
        currentPkgPath: pkgA,
        siblingPatterns: patterns(
          [(path: pkgB, excludes: [])],
          globalExcludes: ['**/*.g.dart'],
        ),
      );
      final files = result.map((r) => r.sourceFile).toList();
      expect(files, contains(p.join(pkgA, 'lib', 'a.dart')));
      expect(files, isNot(contains(p.join(pkgB, 'lib', 'b.g.dart'))));
    });

    test(
      'drops records from packages outside the workspace (not in siblings list)',
      () {
        // Simulates a pub-cache dependency swept in by --coverage-package=.*.
        final pkgC = p.join(base.path, 'pkg_c');
        final records = [
          _rec(p.join(pkgA, 'lib', 'a.dart')),
          _rec(p.join(pkgC, 'lib', 'c.dart')),
        ];
        final result = LcovFilter.filterSiblingExcludes(
          records: records,
          currentPkgPath: pkgA,
          siblingPatterns: patterns([
            (path: pkgB, excludes: ['**']),
          ]),
        );
        final files = result.map((r) => r.sourceFile).toList();
        expect(files, [p.join(pkgA, 'lib', 'a.dart')]);
      },
    );

    // Regression: when the workspace root is the current package, sub-package
    // paths share a common prefix with it. A naive startsWith check would
    // mis-classify sibling files as own-package files and skip filtering them.
    test(
      'filters sibling when current package is a parent directory (workspace root)',
      () {
        // base = workspace root (current package), pkgB is a sub-package of it.
        final records = [
          _rec(p.join(base.path, 'lib', 'root.dart')), // root's own file
          _rec(p.join(pkgB, 'lib', 'gen', 'b.g.dart')), // sibling, excluded
          _rec(p.join(pkgB, 'lib', 'real.dart')), // sibling, kept
        ];
        final result = LcovFilter.filterSiblingExcludes(
          records: records,
          currentPkgPath: base.path,
          siblingPatterns: patterns([
            (
              path: base.path,
              excludes: [],
            ), // current pkg in list (as runner passes it)
            (path: pkgB, excludes: ['lib/gen/**']),
          ]),
        );
        final files = result.map((r) => r.sourceFile).toList();
        expect(files, contains(p.join(base.path, 'lib', 'root.dart')));
        expect(files, contains(p.join(pkgB, 'lib', 'real.dart')));
        expect(files, isNot(contains(p.join(pkgB, 'lib', 'gen', 'b.g.dart'))));
      },
    );

    test('prepareSiblingPatterns output is reusable across multiple '
        'filterSiblingExcludes calls with different currentPkgPath', () {
      // Mirrors FullCoverRunner computing this once and reusing it per package.
      final shared = patterns([
        (path: pkgA, excludes: []),
        (path: pkgB, excludes: ['lib/gen/**']),
      ]);

      final fromA = LcovFilter.filterSiblingExcludes(
        records: [
          _rec(p.join(pkgA, 'lib', 'a.dart')),
          _rec(p.join(pkgB, 'lib', 'gen', 'b.g.dart')),
        ],
        currentPkgPath: pkgA,
        siblingPatterns: shared,
      );
      expect(fromA.map((r) => r.sourceFile), [p.join(pkgA, 'lib', 'a.dart')]);

      final fromB = LcovFilter.filterSiblingExcludes(
        records: [
          _rec(p.join(pkgB, 'lib', 'gen', 'b.g.dart')),
          _rec(p.join(pkgB, 'lib', 'real.dart')),
        ],
        currentPkgPath: pkgB,
        siblingPatterns: shared,
      );
      expect(fromB.map((r) => r.sourceFile), [
        p.join(pkgB, 'lib', 'gen', 'b.g.dart'),
        p.join(pkgB, 'lib', 'real.dart'),
      ]);
    });
  });
}
