import 'dart:io';

import 'package:full_cover/src/config/limits_config.dart';
import 'package:full_cover/src/coverage/lcov_record.dart';
import 'package:full_cover/src/reporter/html_render_context.dart';
import 'package:test/test.dart';

HtmlRenderContext _ctx({LimitsConfig? limits}) => HtmlRenderContext(
  limits: limits ?? const LimitsConfig(),
  pageTemplate: '<title>{{title}}</title>{{assets_prefix}}{{body}}',
);

void main() {
  group('coverageClass', () {
    test('uses defaults when no threshold configured', () {
      final ctx = _ctx();
      expect(ctx.coverageClass(65, null), 'high');
      expect(ctx.coverageClass(45, null), 'medium');
      expect(ctx.coverageClass(20, null), 'low');
    });

    test('uses threshold when configured', () {
      const t = ThresholdConfig(minimum: 50, average: 80);
      final ctx = _ctx();
      expect(ctx.coverageClass(85, t), 'high');
      expect(ctx.coverageClass(60, t), 'medium');
      expect(ctx.coverageClass(40, t), 'low');
    });

    test('boundary: value equal to average is high', () {
      const t = ThresholdConfig(minimum: 50, average: 80);
      expect(_ctx().coverageClass(80, t), 'high');
    });

    test('boundary: value equal to minimum is medium', () {
      const t = ThresholdConfig(minimum: 50, average: 80);
      expect(_ctx().coverageClass(50, t), 'medium');
    });
  });

  group('lineClass', () {
    test('null hits → neutral', () {
      expect(_ctx().lineClass(null, []), 'neutral');
    });

    test('zero hits → miss', () {
      expect(_ctx().lineClass(0, []), 'miss');
    });

    test('hits > 0, no branches → hit', () {
      expect(_ctx().lineClass(3, []), 'hit');
    });

    test('hits > 0, all branches taken → hit', () {
      final branches = [BranchData(1, 0, 0, 1), BranchData(1, 0, 1, 2)];
      expect(_ctx().lineClass(1, branches), 'hit');
    });

    test('hits > 0, some branch not taken → partial', () {
      final branches = [BranchData(1, 0, 0, 1), BranchData(1, 0, 1, 0)];
      expect(_ctx().lineClass(1, branches), 'partial');
    });
  });

  group('splitByPackage', () {
    test('extracts package and short path', () {
      final result = _ctx().splitByPackage(
        '/workspace/packages/my_pkg/lib/src/foo.dart',
      );
      expect(result.package, 'my_pkg');
      expect(result.shortPath, 'foo.dart');
    });

    test('strips src/ prefix from short path', () {
      final result = _ctx().splitByPackage(
        '/workspace/my_pkg/lib/src/util/bar.dart',
      );
      expect(result.shortPath, 'util/bar.dart');
    });

    test('falls back to basename when no /lib/ segment', () {
      final result = _ctx().splitByPackage('some/random/file.dart');
      expect(result.package, '');
      expect(result.shortPath, 'file.dart');
    });
  });

  group('render', () {
    test('replaces template placeholders', () {
      final html = _ctx().render(
        'My Title',
        '<p>body</p>',
        assetsPrefix: 'files/',
      );
      expect(html, contains('My Title'));
      expect(html, contains('<p>body</p>'));
      expect(html, contains('files/'));
    });

    test('escapes HTML in title', () {
      final html = _ctx().render('<script>', '');
      expect(html, contains('&lt;script&gt;'));
    });
  });

  group('escape', () {
    test('escapes all HTML special characters', () {
      final ctx = _ctx();
      expect(ctx.escape('a & b'), 'a &amp; b');
      expect(ctx.escape('<tag>'), '&lt;tag&gt;');
      expect(ctx.escape('"quoted"'), '&quot;quoted&quot;');
    });
  });

  group('pct', () {
    test('formats to one decimal place with % suffix', () {
      expect(_ctx().pct(100.0), '100.0%');
      expect(_ctx().pct(66.666), '66.7%');
      expect(_ctx().pct(0.0), '0.0%');
    });
  });

  group('cellClass', () {
    test('returns cov-prefixed coverage class', () {
      final ctx = _ctx();
      expect(ctx.cellClass(80, null), 'cov-high');
      expect(ctx.cellClass(50, null), 'cov-medium');
      expect(ctx.cellClass(10, null), 'cov-low');
    });
  });

  group('writeMeter', () {
    test('includes label, value and count', () {
      final buf = StringBuffer();
      _ctx().writeMeter(buf, 'Lines', 8, 10, 80.0);
      final html = buf.toString();
      expect(html, contains('Lines'));
      expect(html, contains('80.0%'));
      expect(html, contains('8/10'));
      expect(html, contains('class="meter high"'));
    });

    test('shows threshold chips when configured', () {
      final buf = StringBuffer();
      const t = ThresholdConfig(minimum: 50, average: 80);
      _ctx().writeMeter(buf, 'Lines', 9, 10, 90.0, threshold: t);
      final html = buf.toString();
      expect(html, contains('min 50.0%'));
      expect(html, contains('avg 80.0%'));
      expect(html, contains('threshold-pass'));
    });

    test('marks chip as fail when threshold not met', () {
      final buf = StringBuffer();
      const t = ThresholdConfig(minimum: 80, average: 90);
      _ctx().writeMeter(buf, 'Lines', 5, 10, 50.0, threshold: t);
      final html = buf.toString();
      expect(html, contains('threshold-fail'));
    });
  });

  group('displayPath', () {
    test('returns relative path when rootPath provided', () {
      final ctx = _ctx();
      final root = Directory.systemTemp.path;
      final file = '$root/lib/src/foo.dart';
      final result = ctx.displayPath(file, root);
      expect(result, contains('lib'));
      expect(result, isNot(equals(file)));
    });

    test('returns sourceFile when rootPath is null', () {
      final ctx = _ctx();
      final file = '${Directory.systemTemp.path}/foo.dart';
      expect(ctx.displayPath(file, null), file);
    });
  });

  group('folderPageName', () {
    test('sanitizes special characters', () {
      final name = _ctx().folderPageName('my_pkg', 'lib/src');
      expect(name, startsWith('_dir_'));
      expect(name, endsWith('.html'));
      expect(name, isNot(contains('/')));
    });
  });
}
