import 'receipt_reliability_snapshot.dart';

enum ReceiptReliabilityMetric {
  productTextCoverage,
  recoveredOrphans,
  remainingOrphans,
  completeLines,
  partialLines,
  orphanLines,
}

enum ReceiptReliabilityStatus { improved, unchanged, regressed }

class ReceiptReliabilityComparison {
  const ReceiptReliabilityComparison({
    required this.metric,
    required this.baselineValue,
    required this.currentValue,
    required this.status,
    required this.enforced,
  });

  factory ReceiptReliabilityComparison.fromJson(Map<String, Object?> json) =>
      ReceiptReliabilityComparison(
        metric:
            ReceiptReliabilityMetric.values.byName(json['metric']! as String),
        baselineValue: (json['baselineValue']! as num).toDouble(),
        currentValue: (json['currentValue']! as num).toDouble(),
        status:
            ReceiptReliabilityStatus.values.byName(json['status']! as String),
        enforced: json['enforced']! as bool,
      );

  final ReceiptReliabilityMetric metric;
  final double baselineValue;
  final double currentValue;
  final ReceiptReliabilityStatus status;
  final bool enforced;

  bool get passed => !enforced || status != ReceiptReliabilityStatus.regressed;

  Map<String, Object> toJson() => {
        'metric': metric.name,
        'baselineValue': baselineValue,
        'currentValue': currentValue,
        'status': status.name,
        'enforced': enforced,
      };
}

class ReceiptReliabilityGateResult {
  ReceiptReliabilityGateResult({
    required this.baseline,
    required this.current,
    required Iterable<ReceiptReliabilityComparison> comparisons,
  }) : comparisons = List.unmodifiable(comparisons);

  factory ReceiptReliabilityGateResult.fromJson(Map<String, Object?> json) =>
      ReceiptReliabilityGateResult(
        baseline: ReceiptReliabilitySnapshot.fromJson(
          json['baseline']! as Map<String, Object?>,
        ),
        current: ReceiptReliabilitySnapshot.fromJson(
          json['current']! as Map<String, Object?>,
        ),
        comparisons: (json['comparisons']! as List<Object?>).map(
          (value) => ReceiptReliabilityComparison.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );

  final ReceiptReliabilitySnapshot baseline;
  final ReceiptReliabilitySnapshot current;
  final List<ReceiptReliabilityComparison> comparisons;

  bool get passed => comparisons.every((comparison) => comparison.passed);

  ReceiptReliabilityComparison comparisonFor(
    ReceiptReliabilityMetric metric,
  ) =>
      comparisons.firstWhere((comparison) => comparison.metric == metric);

  Map<String, Object> toJson() => {
        'baseline': baseline.toJson(),
        'current': current.toJson(),
        'comparisons': [
          for (final comparison in comparisons) comparison.toJson(),
        ],
      };

  String toHumanReadableReport() {
    final buffer = StringBuffer()
      ..writeln(current.receiptId)
      ..writeln();
    for (final comparison in comparisons) {
      buffer
        ..writeln(_metricLabel(comparison.metric))
        ..writeln(_formatValue(comparison.metric, comparison.baselineValue))
        ..writeln('→')
        ..writeln(_formatValue(comparison.metric, comparison.currentValue))
        ..writeln(
          '${comparison.status.name.toUpperCase()} — '
          '${comparison.enforced ? (comparison.passed ? 'PASS' : 'FAIL') : 'INFO'}',
        )
        ..writeln();
    }
    buffer.writeln('RELIABILITY GATE: ${passed ? 'PASS' : 'FAIL'}');
    return buffer.toString().trimRight();
  }
}

String _metricLabel(ReceiptReliabilityMetric metric) => switch (metric) {
      ReceiptReliabilityMetric.productTextCoverage => 'Product Text Coverage',
      ReceiptReliabilityMetric.recoveredOrphans => 'Recovered Orphans',
      ReceiptReliabilityMetric.remainingOrphans => 'Remaining Orphans',
      ReceiptReliabilityMetric.completeLines => 'Complete Lines',
      ReceiptReliabilityMetric.partialLines => 'Partial Lines',
      ReceiptReliabilityMetric.orphanLines => 'Orphan Lines',
    };

String _formatValue(ReceiptReliabilityMetric metric, double value) =>
    metric == ReceiptReliabilityMetric.productTextCoverage
        ? '${(value * 100).toStringAsFixed(1)}%'
        : value.toInt().toString();
