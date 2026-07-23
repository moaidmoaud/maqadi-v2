import 'package:flutter/material.dart';

import '../application/receipt_extraction_benchmark_service.dart';
import '../domain/receipt_extraction_benchmark_input.dart';
import '../domain/receipt_extraction_benchmark_result.dart';

class ReceiptExtractionBenchmarkScreen extends StatefulWidget {
  const ReceiptExtractionBenchmarkScreen({
    super.key,
    required this.service,
    required this.input,
  });

  final ReceiptExtractionBenchmarkService service;
  final ReceiptExtractionBenchmarkInput input;

  @override
  State<ReceiptExtractionBenchmarkScreen> createState() =>
      _ReceiptExtractionBenchmarkScreenState();
}

class _ReceiptExtractionBenchmarkScreenState
    extends State<ReceiptExtractionBenchmarkScreen> {
  ReceiptExtractionBenchmarkResult? _result;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _result = null;
      _error = null;
    });
    try {
      final result = await widget.service.analyze(widget.input);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('receipt-extraction-benchmark-screen'),
        appBar: AppBar(title: const Text('Receipt Extraction Benchmark')),
        body: _body(),
      );

  Widget _body() {
    if (_error != null) {
      return Center(
        key: const ValueKey('receipt-extraction-benchmark-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Receipt extraction diagnostics are unavailable.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final result = _result;
    if (result == null) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('receipt-extraction-benchmark-loading'),
        ),
      );
    }
    return _report(result);
  }

  Widget _report(ReceiptExtractionBenchmarkResult result) {
    final metrics = result.metrics;
    return ListView(
      key: const ValueKey('receipt-extraction-benchmark-report'),
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Receipt summary',
          rows: {
            'Receipt': result.receiptId,
            'Store': result.storeName ?? 'Unknown',
            'Receipt Lines': '${metrics.receiptLines}',
            'Product Lines': '${metrics.recoverableProductLines}',
            'Recovered Product Text': '${metrics.linesContainingProductText}',
            'Missing Product Text': '${metrics.linesWithoutProductText}',
            'Coverage': _percent(metrics.productTextCoverage),
          },
        ),
        _Section(
          title: 'Overall metrics',
          rows: {
            'OCR text blocks': '${metrics.ocrTextBlocks}',
            'Receipt Elements': '${metrics.receiptElements}',
            'Receipt Lines': '${metrics.receiptLines}',
            'Lines containing Product Text':
                '${metrics.linesContainingProductText}',
            'Lines without Product Text': '${metrics.linesWithoutProductText}',
            'Product Text Coverage': _percent(metrics.productTextCoverage),
            'Recoverable Product Lines':
                _percent(metrics.recoverableProductLinesPercentage),
            'Duplicate Product Text count':
                '${metrics.duplicateProductTextCount}',
            'Empty Product Text count': '${metrics.emptyProductTextCount}',
          },
        ),
        _Section(
          title: 'Failure breakdown',
          rows: {
            for (final reason in ReceiptExtractionMissingReason.values)
              _reasonLabel(reason): '${result.failureBreakdown[reason] ?? 0}',
          },
        ),
        Text(
          'Missing product lines',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (result.missingLines.isEmpty)
          const Card(
            key: ValueKey('receipt-extraction-no-missing-lines'),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No missing product lines.'),
            ),
          ),
        for (final line in result.missingLines)
          Card(
            key: ValueKey('receipt-extraction-missing-${line.lineId}'),
            child: ListTile(
              title: Text(line.lineId),
              subtitle: Text(
                '${_reasonLabel(line.reason)}\n'
                '${line.summary}\n'
                'Elements: '
                '${line.elementIds.isEmpty ? 'None' : line.elementIds.join(', ')}',
              ),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});

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
                  child: Text('${entry.key}: ${entry.value}'),
                ),
            ],
          ),
        ),
      );
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _reasonLabel(ReceiptExtractionMissingReason reason) => switch (reason) {
      ReceiptExtractionMissingReason.missingOcrText => 'Missing OCR text',
      ReceiptExtractionMissingReason.headerOnly => 'Header only',
      ReceiptExtractionMissingReason.footerOnly => 'Footer only',
      ReceiptExtractionMissingReason.orphanLine => 'Orphan line',
      ReceiptExtractionMissingReason.unresolvedProductText =>
        'Unresolved product text',
      ReceiptExtractionMissingReason.unknown => 'Unknown',
    };
