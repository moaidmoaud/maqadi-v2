import 'receipt_reliability_gate_result.dart';
import 'receipt_reliability_snapshot.dart';

enum ReceiptReliabilityBaselineCompatibility {
  comparable,
  incompatibleBaseline,
  missingBaseline,
}

class ReceiptReliabilityReport {
  const ReceiptReliabilityReport._({
    required this.compatibility,
    required this.current,
    required this.baseline,
    required this.gateResult,
  });

  factory ReceiptReliabilityReport.comparable({
    required ReceiptReliabilityGateResult gateResult,
  }) =>
      ReceiptReliabilityReport._(
        compatibility: ReceiptReliabilityBaselineCompatibility.comparable,
        current: gateResult.current,
        baseline: gateResult.baseline,
        gateResult: gateResult,
      );

  factory ReceiptReliabilityReport.incompatibleBaseline({
    required ReceiptReliabilitySnapshot current,
    required ReceiptReliabilitySnapshot baseline,
  }) =>
      ReceiptReliabilityReport._(
        compatibility:
            ReceiptReliabilityBaselineCompatibility.incompatibleBaseline,
        current: current,
        baseline: baseline,
        gateResult: null,
      );

  factory ReceiptReliabilityReport.missingBaseline({
    required ReceiptReliabilitySnapshot current,
  }) =>
      ReceiptReliabilityReport._(
        compatibility: ReceiptReliabilityBaselineCompatibility.missingBaseline,
        current: current,
        baseline: null,
        gateResult: null,
      );

  factory ReceiptReliabilityReport.fromJson(Map<String, Object?> json) {
    final compatibility = ReceiptReliabilityBaselineCompatibility.values
        .byName(json['compatibility']! as String);
    final current = ReceiptReliabilitySnapshot.fromJson(
      json['current']! as Map<String, Object?>,
    );
    final baselineJson = json['baseline'] as Map<String, Object?>?;
    final gateResultJson = json['gateResult'] as Map<String, Object?>?;
    return ReceiptReliabilityReport._(
      compatibility: compatibility,
      current: current,
      baseline: baselineJson == null
          ? null
          : ReceiptReliabilitySnapshot.fromJson(baselineJson),
      gateResult: gateResultJson == null
          ? null
          : ReceiptReliabilityGateResult.fromJson(gateResultJson),
    );
  }

  final ReceiptReliabilityBaselineCompatibility compatibility;
  final ReceiptReliabilitySnapshot current;
  final ReceiptReliabilitySnapshot? baseline;
  final ReceiptReliabilityGateResult? gateResult;

  String get benchmarkId => current.receiptId;
  String? get baselineId => baseline?.receiptId;
  bool get isComparable =>
      compatibility == ReceiptReliabilityBaselineCompatibility.comparable;
  bool? get passed => gateResult?.passed;

  Map<String, Object?> toJson() => {
        'compatibility': compatibility.name,
        'current': current.toJson(),
        'baseline': baseline?.toJson(),
        'gateResult': gateResult?.toJson(),
      };

  String toHumanReadableReport() {
    final buffer = StringBuffer()
      ..writeln('Benchmark ID: $benchmarkId')
      ..writeln('Baseline ID: ${baselineId ?? 'Not available'}')
      ..writeln('Compatibility: ${compatibility.name}');
    final result = gateResult;
    if (result == null) {
      buffer
        ..writeln()
        ..writeln('No compatible baseline');
      return buffer.toString().trimRight();
    }
    buffer
      ..writeln()
      ..writeln()
      ..writeln(result.toHumanReadableReport());
    return buffer.toString().trimRight();
  }
}
