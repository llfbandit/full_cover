import 'package:full_cover/src/logger.dart';
import 'package:test/test.dart';

void main() {
  List<String> capture(LogLevel level, void Function(Logger) body) {
    final lines = <String>[];
    body(Logger(level: level, sink: lines.add));
    return lines;
  }

  test('verbose shows detail, info and warn', () {
    final lines = capture(LogLevel.verbose, (log) {
      log.detail('d');
      log.info('i');
      log.warn('w');
    });
    expect(lines, ['d', 'i', 'w']);
  });

  test('normal shows info and warn but not detail', () {
    final lines = capture(LogLevel.normal, (log) {
      log.detail('d');
      log.info('i');
      log.warn('w');
    });
    expect(lines, ['i', 'w']);
  });

  test('quiet shows only warn', () {
    final lines = capture(LogLevel.quiet, (log) {
      log.detail('d');
      log.info('i');
      log.warn('w');
    });
    expect(lines, ['w']);
  });

  test('defaults to normal level', () {
    final lines = <String>[];
    final logger = Logger(sink: lines.add);
    logger.detail('d');
    logger.info('i');
    expect(lines, ['i']);
  });

  test('isVerbose reflects the level', () {
    expect(Logger(level: LogLevel.verbose).isVerbose, isTrue);
    expect(Logger(level: LogLevel.normal).isVerbose, isFalse);
    expect(Logger(level: LogLevel.quiet).isVerbose, isFalse);
  });

  test('forwards the message verbatim', () {
    final lines = capture(LogLevel.normal, (log) => log.info('  a\nb'));
    expect(lines.single, '  a\nb');
  });
}
