import 'package:flutter/material.dart';

import '../../receipt_line_builder/domain/receipt_line_result.dart';
import '../../receipt_understanding/domain/receipt_element.dart';
import '../application/orphan_line_diagnostics_service.dart';
import '../domain/orphan_line_diagnostic.dart';

class OrphanLineDiagnosticsScreen extends StatefulWidget {
  const OrphanLineDiagnosticsScreen({
    super.key,
    required this.service,
    required this.elements,
    required this.lineResult,
  });

  final OrphanLineDiagnosticsService service;
  final List<ReceiptElement> elements;
  final ReceiptLineResult lineResult;

  @override
  State<OrphanLineDiagnosticsScreen> createState() =>
      _OrphanLineDiagnosticsScreenState();
}

class _OrphanLineDiagnosticsScreenState
    extends State<OrphanLineDiagnosticsScreen> {
  List<OrphanLineDiagnostic>? _diagnostics;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _diagnostics = null;
      _error = null;
    });
    try {
      final diagnostics = await widget.service.diagnose(
        elements: widget.elements,
        lineResult: widget.lineResult,
      );
      if (!mounted) return;
      setState(() => _diagnostics = diagnostics);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('orphan-line-diagnostics-screen'),
        appBar: AppBar(title: const Text('Orphan Line Diagnostics')),
        body: _body(),
      );

  Widget _body() {
    if (_error != null) {
      return Center(
        key: const ValueKey('orphan-line-diagnostics-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Orphan diagnostics are unavailable.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final diagnostics = _diagnostics;
    if (diagnostics == null) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('orphan-line-diagnostics-loading'),
        ),
      );
    }
    if (diagnostics.isEmpty) {
      return const Center(
        key: ValueKey('orphan-line-diagnostics-empty'),
        child: Text('No orphan receipt lines.'),
      );
    }
    return ListView.builder(
      key: const ValueKey('orphan-line-diagnostics-list'),
      padding: const EdgeInsets.all(12),
      itemCount: diagnostics.length,
      itemBuilder: (context, index) {
        final diagnostic = diagnostics[index];
        return Card(
          key: ValueKey('orphan-diagnostic-${diagnostic.orphanId}'),
          child: ListTile(
            title: Text(diagnostic.orphanId),
            subtitle: Text(
              '${_reasonLabel(diagnostic.rejectionReason)} • '
              '${_recoveryLabel(diagnostic.recoveryPossibility)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDetails(diagnostic),
          ),
        );
      },
    );
  }

  void _showDetails(OrphanLineDiagnostic diagnostic) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          key: ValueKey('orphan-diagnostic-details-${diagnostic.orphanId}'),
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text(
              'Orphan ${diagnostic.orphanId}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _DetailSection(
              title: 'Receipt Elements',
              rows: {
                for (final element in diagnostic.sourceElements)
                  element.id: '${element.type.name} • ${element.text}',
                'Product element exists':
                    _yesNo(diagnostic.productElementExists),
                'Price element exists': _yesNo(diagnostic.priceElementExists),
                'Quantity element exists':
                    _yesNo(diagnostic.quantityElementExists),
              },
            ),
            _DetailSection(
              title: 'Grouping attempt',
              rows: {
                'Candidate product':
                    diagnostic.candidateProductElementId ?? 'None',
                'Same row': _nullableYesNo(diagnostic.sameRow),
                'Same column': _nullableYesNo(diagnostic.sameColumn),
                'Horizontal gap': _metric(diagnostic.horizontalGap),
                'Vertical distance': _metric(diagnostic.verticalDistance),
                'Vertical overlap': _metric(diagnostic.verticalOverlap),
                'Summary': diagnostic.groupingAttemptSummary,
              },
            ),
            _DetailSection(
              title: 'Failure reason',
              rows: {
                'Reason': _reasonLabel(diagnostic.rejectionReason),
              },
            ),
            _DetailSection(
              title: 'Recovery hint',
              rows: {
                'Recoverable': _recoveryLabel(diagnostic.recoveryPossibility),
                'Why': diagnostic.recoveryReason,
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.rows});

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

String _reasonLabel(OrphanLineReason reason) => switch (reason) {
      OrphanLineReason.noProductElement => 'No product element',
      OrphanLineReason.noPriceElement => 'No price element',
      OrphanLineReason.failedRowGrouping => 'Failed row grouping',
      OrphanLineReason.failedColumnGrouping => 'Failed column grouping',
      OrphanLineReason.distanceTooLarge => 'Distance too large',
      OrphanLineReason.overlapTooSmall => 'Overlap too small',
      OrphanLineReason.multipleCompetingCandidates =>
        'Multiple competing candidates',
      OrphanLineReason.unknown => 'Unknown',
    };

String _recoveryLabel(OrphanRecoveryPossibility value) => switch (value) {
      OrphanRecoveryPossibility.yes => 'Yes',
      OrphanRecoveryPossibility.maybe => 'Maybe',
      OrphanRecoveryPossibility.no => 'No',
    };

String _yesNo(bool value) => value ? 'Yes' : 'No';

String _nullableYesNo(bool? value) => value == null ? 'Unknown' : _yesNo(value);

String _metric(double? value) =>
    value == null ? 'Unavailable' : value.toStringAsFixed(3);
