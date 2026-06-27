import 'dart:io';

/// ANSI color and style helpers for console output.
///
/// Styling is disabled automatically when stdout is not a terminal (e.g. when
/// redirected to a file or pipe), when the terminal doesn't support escapes, or
/// when the `NO_COLOR` environment variable is set — so captured or piped
/// output stays clean. Each helper is a no-op passthrough when disabled.
class Ansi {
  final bool enabled;

  Ansi({bool? enabled})
    : enabled =
          enabled ??
          (stdout.hasTerminal &&
              stdout.supportsAnsiEscapes &&
              !Platform.environment.containsKey('NO_COLOR'));

  String _wrap(String code, String text) =>
      enabled ? '\x1B[${code}m$text\x1B[0m' : text;

  String bold(String text) => _wrap('1', text);
  String dim(String text) => _wrap('2', text);
  String red(String text) => _wrap('31', text);
  String green(String text) => _wrap('32', text);
  String yellow(String text) => _wrap('33', text);
  String cyan(String text) => _wrap('36', text);

  /// Bold + cyan, used for section headers.
  String header(String text) => _wrap('1;36', text);
}

/// Shared instance with styling auto-detected from the current stdout.
final ansi = Ansi();
