/// Verbosity levels, ordered from least to most output.
enum LogLevel { quiet, normal, verbose }

/// Leveled sink for console output.
///
/// Each message declares its importance — [warn], [info] or [detail] — and is
/// emitted only when the configured [level] is high enough. The destination
/// [sink] defaults to [print] but can be swapped (e.g. to capture output in
/// tests), keeping I/O out of the domain classes that log.
class Logger {
  final LogLevel level;
  final void Function(String message) _sink;

  const Logger({
    this.level = LogLevel.normal,
    void Function(String message) sink = print,
  }) : _sink = sink;

  /// True when full detail (including streamed test output) should be shown.
  bool get isVerbose => level == LogLevel.verbose;

  /// Warnings — shown at every level, including [LogLevel.quiet].
  void warn(String message) => _emit(LogLevel.quiet, message);

  /// High-level progress — shown at [LogLevel.normal] and above.
  void info(String message) => _emit(LogLevel.normal, message);

  /// Fine-grained detail — shown only at [LogLevel.verbose].
  void detail(String message) => _emit(LogLevel.verbose, message);

  void _emit(LogLevel minimum, String message) {
    if (level.index >= minimum.index) _sink(message);
  }
}
