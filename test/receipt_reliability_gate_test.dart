import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_reliability_gate/application/receipt_reliability_gate.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_gate_result.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_snapshot.dart';

void main() {
  const gate = ReceiptReliabilityGate();
  const baseline = ReceiptReliabilitySnapshot(
    receiptId: 'DAN-0001',
    productTextCoverage: 0.5,
    recoveredOrphans: 1,
    remainingOrphans: 3,
    completeLines: 2,
    partialLines: 2,
    orphanLines: 3,
  );

  test('reports improved metrics and passes the gate', () {
    const current = ReceiptReliabilitySnapshot(
      receiptId: 'DAN-0001',
      productTextCoverage: 0.7,
      recoveredOrphans: 2,
      remainingOrphans: 1,
      completeLines: 3,
      partialLines: 1,
      orphanLines: 1,
    );

    final result = gate.evaluate(baseline: baseline, current: current);

    expect(result.passed, isTrue);
    expect(
      result.comparisons.map((comparison) => comparison.status),
      everyElement(ReceiptReliabilityStatus.improved),
    );
  });

  test('fails when any enforced quality metric regresses', () {
    const current = ReceiptReliabilitySnapshot(
      receiptId: 'DAN-0001',
      productTextCoverage: 0.4,
      recoveredOrphans: 0,
      remainingOrphans: 4,
      completeLines: 2,
      partialLines: 2,
      orphanLines: 4,
    );

    final result = gate.evaluate(baseline: baseline, current: current);

    expect(result.passed, isFalse);
    expect(
      result.comparisonFor(ReceiptReliabilityMetric.productTextCoverage).status,
      ReceiptReliabilityStatus.regressed,
    );
    expect(
      result.comparisonFor(ReceiptReliabilityMetric.recoveredOrphans).status,
      ReceiptReliabilityStatus.regressed,
    );
    expect(
      result.comparisonFor(ReceiptReliabilityMetric.remainingOrphans).status,
      ReceiptReliabilityStatus.regressed,
    );
  });

  test('reports an unchanged baseline without failing', () {
    final result = gate.evaluate(baseline: baseline, current: baseline);

    expect(result.passed, isTrue);
    expect(
      result.comparisons.map((comparison) => comparison.status),
      everyElement(ReceiptReliabilityStatus.unchanged),
    );
  });

  test('snapshot and comparison result serialization remain stable', () {
    final result = gate.evaluate(baseline: baseline, current: baseline);

    final restored = ReceiptReliabilityGateResult.fromJson(result.toJson());

    expect(restored.toJson(), result.toJson());
    expect(
      ReceiptReliabilitySnapshot.fromJson(baseline.toJson()).toJson(),
      baseline.toJson(),
    );
  });

  test('human-readable report includes values, status, and gate outcome', () {
    const current = ReceiptReliabilitySnapshot(
      receiptId: 'DAN-0001',
      productTextCoverage: 0.7,
      recoveredOrphans: 2,
      remainingOrphans: 1,
      completeLines: 3,
      partialLines: 1,
      orphanLines: 1,
    );

    final report = gate
        .evaluate(baseline: baseline, current: current)
        .toHumanReadableReport();

    expect(report, contains('DAN-0001'));
    expect(report, contains('Product Text Coverage'));
    expect(report, contains('50.0%'));
    expect(report, contains('70.0%'));
    expect(report, contains('IMPROVED — PASS'));
    expect(report, contains('RELIABILITY GATE: PASS'));
  });
}
