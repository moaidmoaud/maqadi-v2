import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_reliability_gate/application/receipt_reliability_gate.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_report.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_snapshot.dart';
import 'package:maqadi_v2/receipt_reliability_gate/presentation/receipt_reliability_gate_report_screen.dart';

void main() {
  testWidgets('renders FAIL and regression evidence from the existing report',
      (tester) async {
    const baseline = ReceiptReliabilitySnapshot(
      receiptId: 'DAN-0001',
      productTextCoverage: 0.7,
      recoveredOrphans: 2,
      remainingOrphans: 1,
      completeLines: 3,
      partialLines: 1,
      orphanLines: 1,
    );
    const current = ReceiptReliabilitySnapshot(
      receiptId: 'DAN-0001',
      productTextCoverage: 0.5,
      recoveredOrphans: 1,
      remainingOrphans: 2,
      completeLines: 2,
      partialLines: 2,
      orphanLines: 2,
    );
    final result = ReceiptReliabilityReport.comparable(
      gateResult: const ReceiptReliabilityGate().evaluate(
        baseline: baseline,
        current: current,
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: ReceiptReliabilityGateReportScreen(result: result),
    ));

    expect(
      find.byKey(const ValueKey('receipt-reliability-gate-report-screen')),
      findsOneWidget,
    );
    expect(find.text('FAIL'), findsOneWidget);
    expect(find.textContaining('Product Text Coverage'), findsOneWidget);
    expect(find.textContaining('Recovered Orphans'), findsOneWidget);
    expect(find.textContaining('Remaining Orphans'), findsOneWidget);
    expect(find.textContaining('REGRESSED — FAIL'), findsOneWidget);
    expect(find.textContaining('RELIABILITY GATE: FAIL'), findsOneWidget);
  });

  testWidgets('does not render PASS or FAIL for a missing baseline',
      (tester) async {
    const current = ReceiptReliabilitySnapshot(
      receiptId: 'runtime-receipt',
      productTextCoverage: 0.7,
      recoveredOrphans: 4,
      remainingOrphans: 3,
      completeLines: 7,
      partialLines: 2,
      orphanLines: 3,
    );

    await tester.pumpWidget(MaterialApp(
      home: ReceiptReliabilityGateReportScreen(
        result: ReceiptReliabilityReport.missingBaseline(current: current),
      ),
    ));

    expect(find.text('No compatible baseline'), findsOneWidget);
    expect(find.text('PASS'), findsNothing);
    expect(find.text('FAIL'), findsNothing);
    expect(
        find.textContaining('Benchmark ID: runtime-receipt'), findsOneWidget);
    expect(find.textContaining('Baseline ID: Not available'), findsOneWidget);
    expect(
        find.textContaining('Compatibility: missingBaseline'), findsOneWidget);
  });

  testWidgets('shows both identities for an incompatible baseline',
      (tester) async {
    const current = ReceiptReliabilitySnapshot(
      receiptId: 'runtime-receipt',
      productTextCoverage: 0.7,
      recoveredOrphans: 4,
      remainingOrphans: 3,
      completeLines: 7,
      partialLines: 2,
      orphanLines: 3,
    );
    const baseline = ReceiptReliabilitySnapshot(
      receiptId: 'DAN-0001',
      productTextCoverage: 0.6666666666666666,
      recoveredOrphans: 0,
      remainingOrphans: 1,
      completeLines: 1,
      partialLines: 1,
      orphanLines: 1,
    );

    await tester.pumpWidget(MaterialApp(
      home: ReceiptReliabilityGateReportScreen(
        result: ReceiptReliabilityReport.incompatibleBaseline(
          current: current,
          baseline: baseline,
        ),
      ),
    ));

    expect(find.text('No compatible baseline'), findsOneWidget);
    expect(find.text('PASS'), findsNothing);
    expect(find.text('FAIL'), findsNothing);
    expect(
        find.textContaining('Benchmark ID: runtime-receipt'), findsOneWidget);
    expect(find.textContaining('Baseline ID: DAN-0001'), findsOneWidget);
    expect(
      find.textContaining('Compatibility: incompatibleBaseline'),
      findsOneWidget,
    );
  });
}
