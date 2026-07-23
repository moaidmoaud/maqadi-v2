import 'package:flutter/material.dart';

import '../domain/receipt_reliability_gate_result.dart';

class ReceiptReliabilityGateReportScreen extends StatelessWidget {
  const ReceiptReliabilityGateReportScreen({
    super.key,
    required this.result,
  });

  final ReceiptReliabilityGateResult result;

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('receipt-reliability-gate-report-screen'),
        appBar: AppBar(title: const Text('Receipt Reliability Gate')),
        body: ListView(
          key: const ValueKey('receipt-reliability-gate-report'),
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      result.passed ? Icons.check_circle : Icons.error,
                      color: result.passed ? Colors.green : Colors.red,
                      size: 42,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      result.passed ? 'PASS' : 'FAIL',
                      key: const ValueKey('receipt-reliability-gate-status'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              result.toHumanReadableReport(),
              key: const ValueKey('receipt-reliability-gate-report-text'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      );
}
