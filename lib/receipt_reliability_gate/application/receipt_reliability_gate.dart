import '../../orphan_line_recovery/domain/orphan_line_recovery_result.dart';
import '../../receipt_extraction_benchmark/domain/receipt_extraction_benchmark_result.dart';
import '../../receipt_line_builder/domain/receipt_line_completeness.dart';
import '../domain/receipt_reliability_gate_result.dart';
import '../domain/receipt_reliability_snapshot.dart';

class ReceiptReliabilityGate {
  const ReceiptReliabilityGate();

  ReceiptReliabilitySnapshot capture({
    required String receiptId,
    required ReceiptExtractionBenchmarkResult extraction,
    required OrphanLineRecoveryResult recovery,
  }) {
    final lines = recovery.lines;
    return ReceiptReliabilitySnapshot(
      receiptId: receiptId,
      productTextCoverage: extraction.recoveryComparison.afterRecoveryCoverage,
      recoveredOrphans: extraction.recoveryComparison.recoveredOrphans,
      remainingOrphans: extraction.recoveryComparison.remainingOrphans,
      completeLines: lines
          .where(
              (line) => line.completeness == ReceiptLineCompleteness.complete)
          .length,
      partialLines: lines
          .where((line) => line.completeness == ReceiptLineCompleteness.partial)
          .length,
      orphanLines: lines
          .where((line) => line.completeness == ReceiptLineCompleteness.orphan)
          .length,
    );
  }

  ReceiptReliabilityGateResult evaluate({
    required ReceiptReliabilitySnapshot baseline,
    required ReceiptReliabilitySnapshot current,
  }) {
    _validate(baseline);
    _validate(current);
    if (baseline.receiptId != current.receiptId) {
      throw ArgumentError.value(
        current.receiptId,
        'current.receiptId',
        'Receipt IDs must match before reliability comparison.',
      );
    }
    return ReceiptReliabilityGateResult(
      baseline: baseline,
      current: current,
      comparisons: [
        _compare(
          ReceiptReliabilityMetric.productTextCoverage,
          baseline.productTextCoverage,
          current.productTextCoverage,
          higherIsBetter: true,
          enforced: true,
        ),
        _compare(
          ReceiptReliabilityMetric.recoveredOrphans,
          baseline.recoveredOrphans.toDouble(),
          current.recoveredOrphans.toDouble(),
          higherIsBetter: true,
          enforced: true,
        ),
        _compare(
          ReceiptReliabilityMetric.remainingOrphans,
          baseline.remainingOrphans.toDouble(),
          current.remainingOrphans.toDouble(),
          higherIsBetter: false,
          enforced: true,
        ),
        _compare(
          ReceiptReliabilityMetric.completeLines,
          baseline.completeLines.toDouble(),
          current.completeLines.toDouble(),
          higherIsBetter: true,
          enforced: false,
        ),
        _compare(
          ReceiptReliabilityMetric.partialLines,
          baseline.partialLines.toDouble(),
          current.partialLines.toDouble(),
          higherIsBetter: false,
          enforced: false,
        ),
        _compare(
          ReceiptReliabilityMetric.orphanLines,
          baseline.orphanLines.toDouble(),
          current.orphanLines.toDouble(),
          higherIsBetter: false,
          enforced: false,
        ),
      ],
    );
  }

  ReceiptReliabilityComparison _compare(
    ReceiptReliabilityMetric metric,
    double baseline,
    double current, {
    required bool higherIsBetter,
    required bool enforced,
  }) {
    const epsilon = 0.000000001;
    final difference = current - baseline;
    final status = difference.abs() <= epsilon
        ? ReceiptReliabilityStatus.unchanged
        : (difference > 0) == higherIsBetter
            ? ReceiptReliabilityStatus.improved
            : ReceiptReliabilityStatus.regressed;
    return ReceiptReliabilityComparison(
      metric: metric,
      baselineValue: baseline,
      currentValue: current,
      status: status,
      enforced: enforced,
    );
  }

  void _validate(ReceiptReliabilitySnapshot value) {
    if (value.receiptId.trim().isEmpty ||
        !value.productTextCoverage.isFinite ||
        value.productTextCoverage < 0 ||
        value.productTextCoverage > 1 ||
        value.recoveredOrphans < 0 ||
        value.remainingOrphans < 0 ||
        value.completeLines < 0 ||
        value.partialLines < 0 ||
        value.orphanLines < 0) {
      throw ArgumentError.value(value, 'snapshot', 'Invalid reliability data.');
    }
  }
}
