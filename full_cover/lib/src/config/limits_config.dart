import 'package:yaml/yaml.dart';

class ThresholdConfig {
  static const double defaultMinimum = 30;
  static const double defaultAverage = 60;

  final double? minimum;
  final double? average;

  const ThresholdConfig({this.minimum, this.average});

  double get effectiveMinimum => minimum ?? defaultMinimum;
  double get effectiveAverage => average ?? defaultAverage;

  factory ThresholdConfig.fromYaml(YamlMap? yaml) => ThresholdConfig(
    minimum: (yaml?['minimum'] as num?)?.toDouble(),
    average: (yaml?['average'] as num?)?.toDouble(),
  );
}

class LimitsConfig {
  final ThresholdConfig line;
  final ThresholdConfig branch;
  final ThresholdConfig function;

  const LimitsConfig({
    this.line = const ThresholdConfig(),
    this.branch = const ThresholdConfig(),
    this.function = const ThresholdConfig(),
  });

  factory LimitsConfig.fromYaml(YamlMap? yaml) => LimitsConfig(
    line: ThresholdConfig.fromYaml(yaml?['line'] as YamlMap?),
    branch: ThresholdConfig.fromYaml(yaml?['branch'] as YamlMap?),
    function: ThresholdConfig.fromYaml(yaml?['function'] as YamlMap?),
  );
}
