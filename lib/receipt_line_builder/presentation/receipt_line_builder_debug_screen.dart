import 'package:flutter/material.dart';

import '../../receipt_understanding/domain/receipt_element.dart';
import '../application/receipt_line_builder_service.dart';
import '../domain/receipt_line.dart';
import '../domain/receipt_line_completeness.dart';
import '../domain/receipt_line_debug_trace.dart';
import '../domain/receipt_line_evidence.dart';
import '../domain/receipt_line_failure.dart';
import '../domain/receipt_line_result.dart';
import 'receipt_line_element_highlight.dart';
import 'receipt_line_grouping_overlay.dart';

class ReceiptLineBuilderDebugScreen extends StatefulWidget {
  const ReceiptLineBuilderDebugScreen({
    super.key,
    required this.service,
    required this.elements,
    this.onInspectCandidates,
    this.onInspectExtractionBenchmark,
  });

  final ReceiptLineBuilderService service;
  final List<ReceiptElement> elements;
  final ValueChanged<ReceiptLineResult>? onInspectCandidates;
  final ValueChanged<ReceiptLineResult>? onInspectExtractionBenchmark;

  @override
  State<ReceiptLineBuilderDebugScreen> createState() =>
      _ReceiptLineBuilderDebugScreenState();
}

class _ReceiptLineBuilderDebugScreenState
    extends State<ReceiptLineBuilderDebugScreen> {
  _ReceiptLineDebugView _view = _ReceiptLineDebugView.lines;
  ReceiptLineCompleteness? _filter;
  ReceiptLineResult? _result;
  ReceiptLineFailure? _failure;
  String? _selectedLineId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _result = null;
      _failure = null;
      _selectedLineId = null;
    });
    try {
      final result = await widget.service.build(widget.elements);
      if (!mounted) return;
      setState(() => _result = result);
    } on ReceiptLineFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('receipt-line-builder-debug-screen'),
        appBar: AppBar(
          title: const Text('Receipt line debug'),
          actions: [
            if (_result != null && widget.onInspectExtractionBenchmark != null)
              IconButton(
                key: const ValueKey('open-receipt-extraction-benchmark'),
                tooltip: 'Receipt Extraction Benchmark',
                onPressed: () => widget.onInspectExtractionBenchmark!(_result!),
                icon: const Icon(Icons.analytics_outlined),
              ),
            if (_result != null && widget.onInspectCandidates != null)
              IconButton(
                key: const ValueKey('open-candidate-generation-debug'),
                tooltip: 'Candidate Generation v2',
                onPressed: () => widget.onInspectCandidates!(_result!),
                icon: const Icon(Icons.manage_search),
              ),
            PopupMenuButton<Object>(
              key: const ValueKey('receipt-line-completeness-filter'),
              tooltip: 'Filter completeness',
              onSelected: (value) => setState(() =>
                  _filter = value is ReceiptLineCompleteness ? value : null),
              itemBuilder: (context) => [
                const PopupMenuItem(value: '_all', child: Text('All lines')),
                for (final value in ReceiptLineCompleteness.values)
                  PopupMenuItem(value: value, child: Text(_label(value))),
              ],
              icon:
                  Icon(_filter == null ? Icons.filter_list : Icons.filter_alt),
            ),
          ],
        ),
        body: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<_ReceiptLineDebugView>(
                segments: const [
                  ButtonSegment(
                    value: _ReceiptLineDebugView.elements,
                    label: Text('Elements'),
                  ),
                  ButtonSegment(
                    value: _ReceiptLineDebugView.lines,
                    label: Text('Lines'),
                  ),
                  ButtonSegment(
                    value: _ReceiptLineDebugView.overlay,
                    label: Text('Overlay'),
                  ),
                  ButtonSegment(
                    value: _ReceiptLineDebugView.unassigned,
                    label: Text('Unassigned'),
                  ),
                  ButtonSegment(
                    value: _ReceiptLineDebugView.trace,
                    label: Text('Spatial trace'),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (selection) =>
                    setState(() => _view = selection.single),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      );

  Widget _body() {
    final failure = _failure;
    if (failure != null) {
      return Center(
        key: const ValueKey('receipt-line-builder-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(failure.message),
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
          key: ValueKey('receipt-line-builder-loading'),
        ),
      );
    }
    if (widget.elements.isEmpty) {
      return const Center(
        key: ValueKey('receipt-line-builder-empty'),
        child: Text('No receipt elements are available.'),
      );
    }
    return switch (_view) {
      _ReceiptLineDebugView.elements => _elements(),
      _ReceiptLineDebugView.lines => _lines(result),
      _ReceiptLineDebugView.overlay => Padding(
          padding: const EdgeInsets.all(16),
          child: ReceiptLineGroupingOverlay(
            elements: widget.elements,
            lines: _visible(result.lines),
            selectedLineId: _selectedLineId,
          ),
        ),
      _ReceiptLineDebugView.unassigned => _unassigned(result),
      _ReceiptLineDebugView.trace => _trace(result.debugTrace),
    };
  }

  Widget _trace(ReceiptLineDebugTrace? trace) {
    if (trace == null) {
      return const Center(child: Text('No spatial trace is available.'));
    }
    return ListView(
      key: const ValueKey('receipt-line-spatial-trace'),
      padding: const EdgeInsets.all(12),
      children: [
        _TraceSection(
          title: 'Calibration policy',
          rows: trace.calibrationPolicy.values.map(
            (key, value) => MapEntry(key, value.toStringAsFixed(2)),
          ),
        ),
        _TraceSection(
          title: 'Spatial summary',
          rows: {
            'Median positive height':
                trace.medianPositiveElementHeight?.toStringAsFixed(2) ??
                    'Unavailable',
            'Canonical order': trace.canonicalElementOrder.join(' → '),
            'Complete':
                '${trace.completenessCounts[ReceiptLineCompleteness.complete]}',
            'Partial':
                '${trace.completenessCounts[ReceiptLineCompleteness.partial]}',
            'Orphan':
                '${trace.completenessCounts[ReceiptLineCompleteness.orphan]}',
            'Product anchors': trace.productAnchorIds.join(', '),
          },
        ),
        _TraceSection(
          title: 'Element placement',
          rows: {
            for (final value in trace.elementPlacements)
              value.elementId:
                  value.status == ReceiptElementSpatialStatus.placed
                      ? 'canonical:${value.canonicalIndex}, '
                          'row:${value.rowIndex}, column:${value.columnIndex}'
                      : value.status.name,
          },
        ),
        _TraceSection(
          title: 'Row decisions',
          rows: {
            for (var index = 0; index < trace.rowDecisions.length; index++)
              '$index: ${trace.rowDecisions[index].previousElementId} → '
                      '${trace.rowDecisions[index].currentElementId}':
                  '${trace.rowDecisions[index].split ? 'SPLIT' : 'JOIN'}, '
                      'vertical=${trace.rowDecisions[index].normalizedVerticalDistance.toStringAsFixed(3)}, '
                      'overlap=${trace.rowDecisions[index].verticalOverlapRatio.toStringAsFixed(3)}, '
                      'row=${trace.rowDecisions[index].resultingRowIndex}',
          },
        ),
        _TraceSection(
          title: 'Column decisions',
          rows: {
            for (var index = 0; index < trace.columnDecisions.length; index++)
              '$index: ${trace.columnDecisions[index].previousElementId} → '
                      '${trace.columnDecisions[index].currentElementId}':
                  '${trace.columnDecisions[index].split ? 'SPLIT' : 'JOIN'}, '
                      'gap=${trace.columnDecisions[index].normalizedHorizontalGap.toStringAsFixed(3)}, '
                      'row=${trace.columnDecisions[index].rowIndex}, '
                      'column=${trace.columnDecisions[index].resultingColumnIndex}',
          },
        ),
        _TraceSection(
          title: 'Line roles and rejected candidates',
          rows: {
            for (final value in trace.lineRoles)
              value.lineId: 'anchor=${value.productAnchorId ?? 'None'}, '
                  'roles=${_nullableStrings(value.roleElementIds)}, '
                  'rejected=${_strings(value.rejectedCandidates)}, '
                  'completeness=${_label(value.completeness)}',
          },
        ),
        _DecisionTraceSection(traces: trace.decisionTraces),
        _TraceSection(
          title: 'Unassigned elements',
          rows: {
            for (final value in trace.unassignedElements)
              value.elementId: value.reasonCode,
          },
        ),
      ],
    );
  }

  Widget _elements() => ListView(
        key: const ValueKey('receipt-line-source-elements'),
        padding: const EdgeInsets.all(12),
        children: [
          ReceiptLineElementHighlight(
            elements: widget.elements,
            highlightedElementIds:
                _selectedLine?.referencedElementIds.toSet() ?? {},
          ),
        ],
      );

  Widget _lines(ReceiptLineResult result) {
    final lines = _visible(result.lines);
    if (lines.isEmpty) {
      return const Center(child: Text('No lines match this filter.'));
    }
    return ListView.builder(
      key: const ValueKey('receipt-lines'),
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        return Card(
          key: ValueKey('receipt-line-${line.id}'),
          child: ListTile(
            selected: line.id == _selectedLineId,
            title: Text('${_label(line.completeness)} line'),
            subtitle: Text(line.referencedElementIds.join(', ')),
            onTap: () => setState(() => _selectedLineId = line.id),
            trailing: IconButton(
              key: ValueKey('receipt-line-evidence-${line.id}'),
              tooltip: 'Grouping evidence',
              onPressed: () => _showEvidence(line.evidence, line: line),
              icon: const Icon(Icons.info_outline),
            ),
          ),
        );
      },
    );
  }

  Widget _unassigned(ReceiptLineResult result) {
    if (result.unassignedElements.isEmpty) {
      return const Center(child: Text('No unassigned elements.'));
    }
    return ListView.builder(
      key: const ValueKey('receipt-line-unassigned-elements'),
      padding: const EdgeInsets.all(12),
      itemCount: result.unassignedElements.length,
      itemBuilder: (context, index) {
        final value = result.unassignedElements[index];
        return Card(
          child: ListTile(
            title: Text(value.elementId),
            subtitle: Text(value.reasonCode.name),
            trailing: IconButton(
              key: ValueKey('unassigned-evidence-${value.elementId}'),
              tooltip: 'Unassigned evidence',
              onPressed: () => _showEvidence(value.evidence),
              icon: const Icon(Icons.info_outline),
            ),
          ),
        );
      },
    );
  }

  List<ReceiptLine> _visible(List<ReceiptLine> lines) => _filter == null
      ? lines
      : lines.where((line) => line.completeness == _filter).toList();

  ReceiptLine? get _selectedLine {
    final result = _result;
    if (result == null || _selectedLineId == null) return null;
    for (final line in result.lines) {
      if (line.id == _selectedLineId) return line;
    }
    return null;
  }

  void _showEvidence(ReceiptLineEvidence evidence, {ReceiptLine? line}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Grouping evidence',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (line != null) ...[
              _EvidenceRow('Completeness', _label(line.completeness)),
              _EvidenceRow('Product', line.productElementId ?? 'None'),
              _EvidenceRow('Price', line.priceElementId ?? 'None'),
              _EvidenceRow('Quantity', line.quantityElementId ?? 'None'),
              _EvidenceRow('Discount', line.discountElementId ?? 'None'),
              _EvidenceRow('Tax', line.taxElementId ?? 'None'),
              _EvidenceRow('Line total', line.lineTotalElementId ?? 'None'),
            ],
            _EvidenceRow('Anchor', evidence.anchorElementId ?? 'None'),
            _EvidenceRow('Attached', evidence.attachedElementIds.join(', ')),
            _EvidenceRow('Rule', evidence.appliedGroupingRule),
            _EvidenceRow(
                'Vertical', _metrics(evidence.normalizedVerticalDistances)),
            _EvidenceRow(
                'Horizontal', _metrics(evidence.normalizedHorizontalDistances)),
            _EvidenceRow('Overlap', _metrics(evidence.overlapMetrics)),
            _EvidenceRow('Row / column', _strings(evidence.columnEvidence)),
            _EvidenceRow('Rejected', _strings(evidence.rejectedCandidates)),
            _EvidenceRow('Factors', evidence.confidenceFactors.join(', ')),
            const SizedBox(height: 8),
            Text(evidence.summary),
          ],
        ),
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 105, child: Text(label)),
            Expanded(
              child: Text(value.isEmpty ? 'None' : value,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
}

enum _ReceiptLineDebugView { elements, lines, overlay, unassigned, trace }

String _label(ReceiptLineCompleteness value) => switch (value) {
      ReceiptLineCompleteness.complete => 'Complete',
      ReceiptLineCompleteness.partial => 'Partial',
      ReceiptLineCompleteness.orphan => 'Orphan',
    };

String _metrics(Map<String, double> values) => values.entries
    .map((entry) => '${entry.key}: ${entry.value.toStringAsFixed(2)}')
    .join(', ');

String _strings(Map<String, String> values) =>
    values.entries.map((entry) => '${entry.key}: ${entry.value}').join(', ');

String _nullableStrings(Map<String, String?> values) => values.entries
    .map((entry) => '${entry.key}: ${entry.value ?? 'None'}')
    .join(', ');

class _TraceSection extends StatelessWidget {
  const _TraceSection({required this.title, required this.rows});

  final String title;
  final Map<String, String> rows;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (rows.isEmpty) const Text('None'),
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

class _DecisionTraceSection extends StatelessWidget {
  const _DecisionTraceSection({required this.traces});

  final List<ReceiptAnchorDecisionTrace> traces;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('receipt-line-decision-trace'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Decision Trace',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (traces.isEmpty) const Text('None'),
              for (final trace in traces) ...[
                Text(
                  'Line ${trace.lineId} · Anchor ${trace.anchorElementId}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (trace.candidateEvaluations.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('No candidates evaluated.'),
                  ),
                for (final candidate in trace.candidateEvaluations)
                  Padding(
                    key: ValueKey(
                      'candidate-decision-${trace.anchorElementId}-'
                      '${candidate.candidateElementId}-'
                      '${candidate.evaluationOrder}',
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '#${candidate.evaluationOrder} '
                      '${candidate.candidateElementId} '
                      '(${candidate.candidateType.name}) · '
                      '${candidate.accepted ? 'ACCEPTED' : 'REJECTED'} · '
                      '${candidate.decisionReason.name} · '
                      'sameRow=${candidate.sameRow}, '
                      'sameColumn=${candidate.sameColumn}, '
                      'row=${candidate.rowIndex}, '
                      'column=${candidate.columnIndex}, '
                      'horizontalGap='
                      '${candidate.horizontalGap.toStringAsFixed(3)}, '
                      'verticalDistance='
                      '${candidate.verticalDistance.toStringAsFixed(3)}, '
                      'verticalOverlap='
                      '${candidate.verticalOverlap.toStringAsFixed(3)}, '
                      'score=${candidate.spatialScore.toStringAsFixed(3)}',
                    ),
                  ),
                const Divider(),
              ],
            ],
          ),
        ),
      );
}
