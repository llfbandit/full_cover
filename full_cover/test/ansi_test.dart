import 'package:full_cover/src/ansi.dart';
import 'package:test/test.dart';

void main() {
  group('when enabled', () {
    final ansi = Ansi(enabled: true);

    test('wraps each style with the matching SGR code', () {
      expect(ansi.bold('x'), '\x1B[1mx\x1B[0m');
      expect(ansi.dim('x'), '\x1B[2mx\x1B[0m');
      expect(ansi.red('x'), '\x1B[31mx\x1B[0m');
      expect(ansi.green('x'), '\x1B[32mx\x1B[0m');
      expect(ansi.yellow('x'), '\x1B[33mx\x1B[0m');
      expect(ansi.cyan('x'), '\x1B[36mx\x1B[0m');
    });

    test('header combines bold and cyan', () {
      expect(ansi.header('title'), '\x1B[1;36mtitle\x1B[0m');
    });

    test('styles can be nested', () {
      expect(ansi.green(ansi.bold('x')), '\x1B[32m\x1B[1mx\x1B[0m\x1B[0m');
    });
  });

  group('when disabled', () {
    final ansi = Ansi(enabled: false);

    test('returns the text unchanged', () {
      expect(ansi.bold('x'), 'x');
      expect(ansi.red('x'), 'x');
      expect(ansi.header('title'), 'title');
      expect(ansi.green(ansi.bold('x')), 'x');
    });
  });
}
