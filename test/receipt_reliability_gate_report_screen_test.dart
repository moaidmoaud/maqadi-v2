import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_reliability_gate/application/receipt_reliability_gate.dart';
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
    final result = const ReceiptReliabilityGate().evaluate(
      baseline: baseline,
      current: current,
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
}
