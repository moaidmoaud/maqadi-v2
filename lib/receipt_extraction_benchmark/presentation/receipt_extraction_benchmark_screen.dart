import 'package:flutter/material.dart';

import '../../receipt_reliability_gate/application/receipt_reliability_report_service.dart';
import '../../receipt_reliability_gate/domain/receipt_reliability_gate_result.dart';
import '../../receipt_reliability_gate/presentation/receipt_reliability_gate_report_screen.dart';
import '../application/receipt_extraction_benchmark_service.dart';
import '../domain/receipt_extraction_benchmark_input.dart';
import '../domain/receipt_extraction_benchmark_result.dart';

class ReceiptExtractionBenchmarkScreen extends StatefulWidget {
  const ReceiptExtractionBenchmarkScreen({
    super.key,
    required this.service,
    required this.input,
    this.reliabilityReportService,
  });

  final ReceiptExtractionBenchmarkService service;
  final ReceiptExtractionBenchmarkInput input;
  final ReceiptReliabilityReportService? reliabilityReportService;

  @override
  State<ReceiptExtractionBenchmarkScreen> createState() =>
      _ReceiptExtractionBenchmarkScreenState();
}

class _ReceiptExtractionBenchmarkScreenState
    extends State<ReceiptExtractionBenchmarkScreen> {
  ReceiptExtractionBenchmarkResult? _result;
  ReceiptReliabilityGateResult? _reliabilityResult;
  Object? _error;
  Object? _reliabilityError;
  bool _loadingReliabilityReport = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _result = null;
      _reliabilityResult = null;
      _error = null;
      _reliabilityError = null;
    });
    try {
      final result = await widget.service.analyze(widget.input);
      if (!mounted) return;
      setState(() => _result = result);
      await _loadReliabilityReport(result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('receipt-extraction-benchmark-screen'),
        appBar: AppBar(
          title: const Text('Receipt Extraction Benchmark'),
          actions: [
            if (_reliabilityResult != null)
              IconButton(
                key: const ValueKey('open-receipt-reliability-gate-report'),
                tooltip: 'Receipt Reliability Gate',
                onPressed: _openReliabilityReport,
                icon: const Icon(Icons.verified_outlined),
              ),
          ],
        ),
        body: _body(),
      );

  Future<void> _loadReliabilityReport(
    ReceiptExtractionBenchmarkResult extraction,
  ) async {
    final service = widget.reliabilityReportService;
    if (service == null) return;
    setState(() {
      _loadingReliabilityReport = true;
      _reliabilityError = null;
    });
    try {
      final result = await service.generate(
        input: widget.input,
        extraction: extraction,
      );
      if (!mounted) return;
      setState(() => _reliabilityResult = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _reliabilityError = error);
    } finally {
      if (mounted) setState(() => _loadingReliabilityReport = false);
    }
  }

  void _openReliabilityReport() {
    final result = _reliabilityResult;
    if (result == null) return;
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => ReceiptReliabilityGateReportScreen(result: result),
    ));
  }

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
        _Section(
          title: 'Orphan Recovery Summary',
          rows: {
            'Recoverable': '${result.orphanRecoverySummary.recoverable}',
            'Maybe Recoverable':
                '${result.orphanRecoverySummary.maybeRecoverable}',
            'Unrecoverable': '${result.orphanRecoverySummary.unrecoverable}',
          },
        ),
        _Section(
          title: 'Recovery comparison',
          rows: {
            'Before Recovery':
                _percent(result.recoveryComparison.beforeRecoveryCoverage),
            'After Recovery':
                _percent(result.recoveryComparison.afterRecoveryCoverage),
            'Coverage Improvement':
                _signedPercent(result.recoveryComparison.coverageImprovement),
            'Recovered Orphans':
                '${result.recoveryComparison.recoveredOrphans}',
            'Remaining Orphans':
                '${result.recoveryComparison.remainingOrphans}',
          },
        ),
        if (widget.reliabilityReportService != null)
          _reliabilityReportSection(result),
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

  Widget _reliabilityReportSection(
    ReceiptExtractionBenchmarkResult extraction,
  ) {
    if (_loadingReliabilityReport) {
      return const Card(
        key: ValueKey('receipt-reliability-gate-inline-loading'),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading Reliability Gate report…'),
            ],
          ),
        ),
      );
    }
    if (_reliabilityError != null) {
      return Card(
        key: const ValueKey('receipt-reliability-gate-inline-error'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reliability Gate',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Reliability report is unavailable.'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _loadReliabilityReport(extraction),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final reliability = _reliabilityResult;
    if (reliability == null) return const SizedBox.shrink();
    return Card(
      key: const ValueKey('receipt-reliability-gate-inline-report'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reliability Gate',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  reliability.passed ? Icons.check_circle : Icons.error,
                  color: reliability.passed ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  reliability.passed ? 'PASS' : 'FAIL',
                  key: const ValueKey(
                    'receipt-reliability-gate-inline-status',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              reliability.toHumanReadableReport(),
              key: const ValueKey(
                'receipt-reliability-gate-inline-report-text',
              ),
            ),
          ],
        ),
      ),
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

String _signedPercent(double value) {
  final prefix = value > 0 ? '+' : '';
  return '$prefix${_percent(value)}';
}

String _reasonLabel(ReceiptExtractionMissingReason reason) => switch (reason) {
      ReceiptExtractionMissingReason.missingOcrText => 'Missing OCR text',
      ReceiptExtractionMissingReason.headerOnly => 'Header only',
      ReceiptExtractionMissingReason.footerOnly => 'Footer only',
      ReceiptExtractionMissingReason.orphanLine => 'Orphan line',
      ReceiptExtractionMissingReason.unresolvedProductText =>
        'Unresolved product text',
      ReceiptExtractionMissingReason.unknown => 'Unknown',
    };
