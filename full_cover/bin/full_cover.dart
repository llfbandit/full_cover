import 'dart:io';

import 'package:args/args.dart';
import 'package:full_cover/full_cover.dart';

void main(List<String> arguments) async {
  final argParser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'full_cover.yaml',
      help: 'Path to the full_cover.yaml config file.',
    )
    ..addFlag(
      'no-test',
      negatable: false,
      help: 'Skip running tests; use existing coverage/lcov.info files.',
    )
    ..addFlag(
      'clean',
      negatable: false,
      help: 'Remove coverage output folders and exit.',
    )
    ..addOption(
      'concurrency',
      abbr: 'j',
      help: 'Number of concurrent test suites (passed to dart/flutter test).',
      valueHelp: 'jobs',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Print full detail, including test output.',
    )
    ..addFlag(
      'quiet',
      abbr: 'q',
      negatable: false,
      help: 'Only print warnings and errors.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message.',
    );

  final ArgResults results;
  try {
    results = argParser.parse(arguments);
  } on FormatException catch (e) {
    print(ansi.red('Error: ${e.message}'));
    print(argParser.usage);
    exit(1);
  }

  if (results['help'] as bool) {
    print(ansi.header('full_cover — Dart/Flutter workspace coverage tool\n'));
    print(argParser.usage);
    exit(0);
  }

  final configPath = results['config'] as String;
  final clean = results['clean'] as bool;
  final skipTests = results['no-test'] as bool;
  final verbose = results['verbose'] as bool;
  final quiet = results['quiet'] as bool;
  final concurrency = results['concurrency'] as String?;

  final level = verbose
      ? LogLevel.verbose
      : quiet
      ? LogLevel.quiet
      : LogLevel.normal;

  final FullCoverConfig config;
  try {
    config = FullCoverConfig.fromFile(configPath);
  } catch (e) {
    print(ansi.red('Error loading config: $e'));
    exit(1);
  }

  try {
    final runner = FullCoverRunner(
      level: level,
      skipTests: skipTests,
      concurrency: concurrency,
    );
    if (clean) {
      await runner.clean(config);
    } else {
      await runner.run(config);
    }
  } catch (e, st) {
    print(ansi.red('Error: $e'));
    if (verbose) print(ansi.dim('$st'));
    exit(1);
  }
}
