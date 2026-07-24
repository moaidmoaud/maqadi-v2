import 'package:flutter/material.dart';

import '../domain/receipt_reliability_report.dart';

class ReceiptReliabilityGateReportScreen extends StatelessWidget {
  const ReceiptReliabilityGateReportScreen({
    super.key,
    required this.result,
  });

  final ReceiptReliabilityReport result;

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
                    Icon(_icon, color: _color, size: 42),
                    const SizedBox(height: 8),
                    Text(
                      _status,
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

  String get _status {
    if (!result.isComparable) return 'No compatible baseline';
    return result.passed! ? 'PASS' : 'FAIL';
  }

  IconData get _icon => !result.isComparable
      ? Icons.info_outline
      : result.passed!
          ? Icons.check_circle
          : Icons.error;

  Color get _color => !result.isComparable
      ? Colors.orange
      : result.passed!
          ? Colors.green
          : Colors.red;
}
