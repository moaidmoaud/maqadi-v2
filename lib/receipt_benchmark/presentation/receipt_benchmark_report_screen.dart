import 'package:flutter/material.dart';

import '../application/receipt_benchmark_runner.dart';
import '../domain/receipt_benchmark_definition.dart';
import '../domain/receipt_benchmark_failure.dart';
import '../domain/receipt_benchmark_result.dart';
import 'receipt_benchmark_overlay.dart';

class ReceiptBenchmarkReportScreen extends StatefulWidget {
  const ReceiptBenchmarkReportScreen({
    super.key,
    required this.runner,
    required this.definition,
  });

  final ReceiptBenchmarkRunner runner;
  final ReceiptBenchmarkDefinition definition;

  @override
  State<ReceiptBenchmarkReportScreen> createState() =>
      _ReceiptBenchmarkReportScreenState();
}

class _ReceiptBenchmarkReportScreenState
    extends State<ReceiptBenchmarkReportScreen> {
  ReceiptBenchmarkResult? _result;
  ReceiptBenchmarkFailure? _failure;
  ReceiptBenchmarkOverlayMode _overlayMode =
      ReceiptBenchmarkOverlayMode.mismatches;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _result = null;
      _failure = null;
    });
    try {
      final result = await widget.runner.run(widget.definition);
      if (!mounted) return;
      setState(() => _result = result);
    } on ReceiptBenchmarkFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('receipt-benchmark-report-screen'),
        appBar: AppBar(title: Text('Benchmark ${widget.definition.receiptId}')),
        body: _body(),
      );

  Widget _body() {
    final failure = _failure;
    if (failure != null) {
      return Center(
        key: const ValueKey('receipt-benchmark-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(failure.message),
            const SizedBox(height: 12),
            FilledButton(onPressed: _run, child: const Text('Retry')),
          ],
        ),
      );
    }
    final result = _result;
    if (result == null) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('receipt-benchmark-loading'),
        ),
      );
    }
    return ListView(
      key: const ValueKey('receipt-benchmark-report'),
      padding: const EdgeInsets.all(16),
      children: [
        _ReportSection(
          title: 'Benchmark',
          rows: {
            'Receipt ID': result.definition.receiptId,
            'Result version': result.resultVersion,
            'Fixture version': result.definition.fixtureVersion,
            'Ground truth scope': result.definition.groundTruth.scope,
            'OCR accuracy': result.understanding.ocrAccuracy == null
                ? 'Unavailable'
                : _percent(result.understanding.ocrAccuracy!),
          },
        ),
        _ReportSection(
          title: 'Calibration policy',
          rows: result.policy.values
              .map((key, value) => MapEntry(key, value.toStringAsFixed(3))),
        ),
        _ReportSection(
          title: 'Metrics',
          rows: {
            'Expected elements': '${result.understanding.expectedElementCount}',
            'Actual elements': '${result.understanding.actualElementCount}',
            'Correct elements':
                '${result.understanding.correctlyClassifiedElements}',
            'Misclassified elements':
                '${result.understanding.misclassifiedElements.length}',
            'Unknown elements': '${result.understanding.unknownCount}',
            'Understanding accuracy':
                _percent(result.metrics.understandingAccuracy),
            'Line precision': _percent(result.metrics.lineGroupingPrecision),
            'Line recall': _percent(result.metrics.lineGroupingRecall),
            'Line F1': _percent(result.metrics.lineGroupingF1),
            'Correct lines': '${result.metrics.correctLineCount}',
            'Expected lines': '${result.metrics.expectedLineCount}',
            'Actual lines': '${result.metrics.actualLineCount}',
            'Expected unassigned':
                '${result.definition.groundTruth.expectedUnassignedKeys.length}',
            'Unassigned': '${result.metrics.unassignedCount}',
            'Manual corrections estimate':
                '${result.metrics.manualCorrectionsEstimate}',
          },
        ),
        Text('Calibration notes',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(result.definition.calibrationNotes),
        const SizedBox(height: 18),
        SegmentedButton<ReceiptBenchmarkOverlayMode>(
          segments: const [
            ButtonSegment(
              value: ReceiptBenchmarkOverlayMode.expected,
              label: Text('Expected'),
            ),
            ButtonSegment(
              value: ReceiptBenchmarkOverlayMode.actual,
              label: Text('Actual'),
            ),
            ButtonSegment(
              value: ReceiptBenchmarkOverlayMode.mismatches,
              label: Text('Mismatches'),
            ),
          ],
          selected: {_overlayMode},
          onSelectionChanged: (selection) =>
              setState(() => _overlayMode = selection.single),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 320,
          child: ReceiptBenchmarkOverlay(
            result: result,
            mode: _overlayMode,
          ),
        ),
        _ReportSection(
          title: 'Detailed mismatches',
          rows: {
            'Misclassified elements': result.understanding.misclassifiedElements
                .map((value) => value.fixtureKey)
                .join(', '),
            'Missing elements':
                result.understanding.missingExpectedElements.join(', '),
            'Unexpected elements':
                result.understanding.unexpectedElements.join(', '),
            'Missing lines': result.lines.missingExpectedLines.join(', '),
            'Unexpected lines': result.lines.unexpectedLines.join(', '),
            'Wrong role attachments': result.lines.incorrectRoleAttachments
                .map((value) => '${value.expectedLineKey}:${value.role}')
                .join(', '),
            'Completeness mismatches':
                result.lines.completenessMismatches.join(', '),
            'Missing unassigned':
                result.lines.missingExpectedUnassigned.join(', '),
            'Unexpected unassigned':
                result.lines.unexpectedUnassigned.join(', '),
          },
        ),
      ],
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.title, required this.rows});

  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final entry in rows.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${entry.key}: ${entry.value.isEmpty ? 'None' : entry.value}',
                  ),
                ),
            ],
          ),
        ),
      );
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
