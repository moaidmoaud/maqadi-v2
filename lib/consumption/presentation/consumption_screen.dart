import 'package:flutter/material.dart';

import '../application/consumption_service.dart';
import '../domain/consumption_event.dart';
import '../domain/consumption_failure.dart';
import '../domain/consumption_profile.dart';
import '../domain/consumption_result.dart';

class ConsumptionScreen extends StatefulWidget {
  const ConsumptionScreen({super.key, required this.service});

  final ConsumptionService service;

  @override
  State<ConsumptionScreen> createState() => _ConsumptionScreenState();
}

class _ConsumptionScreenState extends State<ConsumptionScreen> {
  int _loadVersion = 0;
  bool _loading = true;
  List<ConsumptionResult> _results = const [];
  Map<String, ConsumptionFailure> _itemFailures = const {};
  ConsumptionFailure? _failure;
  String? _selectedProductId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _failure = null;
    });
    final evaluation = await widget.service.evaluateInventory();
    if (!mounted || version != _loadVersion) return;
    setState(() {
      _loading = false;
      switch (evaluation) {
        case ConsumptionEvaluationSuccess(:final results, :final failures):
          _results = results;
          _itemFailures = failures;
          final availableIds = {
            ...results.map((result) => result.snapshot.productId),
            ...failures.keys,
          };
          if (!availableIds.contains(_selectedProductId)) {
            _selectedProductId = availableIds.firstOrNull;
          }
        case ConsumptionEvaluationFailure(:final failure):
          _results = const [];
          _itemFailures = const {};
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Consumption history'),
          actions: [
            IconButton(
              key: const ValueKey('consumption-refresh'),
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _body(),
      );

  Widget _body() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(key: ValueKey('consumption-loading')),
      );
    }
    final failure = _failure;
    if (failure != null) {
      return _MessageState(
        key: const ValueKey('consumption-error'),
        icon: Icons.error_outline,
        title: 'Consumption history is unavailable',
        message: failure.message,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_results.isEmpty && _itemFailures.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: const _ScrollableMessage(
          key: ValueKey('consumption-empty'),
          icon: Icons.inventory_2_outlined,
          title: 'No inventory products',
          message: 'Add a product before reviewing consumption history.',
        ),
      );
    }

    final options = <_ProductOption>[
      for (final result in _results)
        _ProductOption(result.snapshot.productId, result.snapshot.productName),
      for (final productId in _itemFailures.keys)
        if (!_results.any((result) => result.snapshot.productId == productId))
          _ProductOption(productId, productId),
    ];
    final selectedId = _selectedProductId ?? options.first.id;
    final selectedResult = _resultFor(selectedId);
    final selectedFailure = _itemFailures[selectedId];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          DropdownButtonFormField<String>(
            key: const ValueKey('consumption-product-selector'),
            initialValue: selectedId,
            decoration: const InputDecoration(
              labelText: 'Product',
              prefixIcon: Icon(Icons.inventory_2_outlined),
            ),
            items: [
              for (final option in options)
                DropdownMenuItem(value: option.id, child: Text(option.name)),
            ],
            onChanged: (value) => setState(() => _selectedProductId = value),
          ),
          const SizedBox(height: 16),
          if (selectedFailure != null)
            _MessageState(
              key: const ValueKey('consumption-item-error'),
              icon: Icons.warning_amber_outlined,
              title: 'This history cannot be evaluated',
              message: selectedFailure.message,
            )
          else if (selectedResult != null) ...[
            _HistorySummary(result: selectedResult),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('consumption-explanation'),
              onPressed: () => _showExplanation(selectedResult.explanation),
              icon: const Icon(Icons.info_outline),
              label: const Text('Consumption explanation'),
            ),
            const SizedBox(height: 12),
            if (selectedResult.profile.events.isEmpty)
              const _MessageState(
                key: ValueKey('consumption-no-history'),
                icon: Icons.history_toggle_off,
                title: 'No quantity-change history',
                message: 'No consumption events have been recorded yet.',
              )
            else
              for (final event in selectedResult.profile.events.reversed) ...[
                _ConsumptionEventCard(event: event),
                const SizedBox(height: 8),
              ],
          ],
        ],
      ),
    );
  }

  ConsumptionResult? _resultFor(String productId) {
    for (final result in _results) {
      if (result.snapshot.productId == productId) return result;
    }
    return null;
  }

  void _showExplanation(ConsumptionExplanation explanation) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Consumption explanation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _DetailRow('Pattern', _patternLabel(explanation.pattern)),
              _DetailRow('Reason', explanation.reasonCode.name),
              _DetailRow('Events', '${explanation.eventCount}'),
              _DetailRow(
                'Consumption events',
                '${explanation.consumptionEventCount}',
              ),
              _DetailRow(
                'Observation period',
                _period(explanation.observationPeriod),
              ),
              if (explanation.summary != null) ...[
                const SizedBox(height: 8),
                Text(explanation.summary!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.result});

  final ConsumptionResult result;

  @override
  Widget build(BuildContext context) {
    final profile = result.profile;
    return Card(
      key: const ValueKey('consumption-summary'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.snapshot.productName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(_patternLabel(result.explanation.pattern)),
            const SizedBox(height: 12),
            _DetailRow(
              'Observed consumption',
              '${_number(profile.totalConsumed)} ${profile.unit}',
            ),
            _DetailRow(
              'Consumption events',
              '${profile.consumptionEventCount}',
            ),
            _DetailRow(
              'Starting quantity',
              '${_number(profile.startingQuantity)} ${profile.unit}',
            ),
            _DetailRow(
              'Current quantity',
              '${_number(profile.currentQuantity)} ${profile.unit}',
            ),
            _DetailRow(
              'Observation period',
              _period(result.explanation.observationPeriod),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsumptionEventCard extends StatelessWidget {
  const _ConsumptionEventCard({required this.event});

  final ConsumptionEvent event;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey('consumption-event-${event.id}'),
        child: ListTile(
          leading:
              Icon(event.delta < 0 ? Icons.remove_circle : Icons.add_circle),
          title: Text(_reasonLabel(event.reason)),
          subtitle: Text(
            '${event.timestamp.toLocal()}\n'
            '${_number(event.previousQuantity)} → '
            '${_number(event.currentQuantity)} ${event.unit}',
          ),
          trailing: Text(
            '${event.delta > 0 ? '+' : ''}${_number(event.delta)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          isThreeLine: true,
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 140, child: Text(label)),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: _MessageState(icon: icon, title: title, message: message),
          ),
        ],
      );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center),
              if (actionLabel != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
}

class _ProductOption {
  const _ProductOption(this.id, this.name);

  final String id;
  final String name;
}

String _patternLabel(ConsumptionPattern pattern) => switch (pattern) {
      ConsumptionPattern.noHistory => 'No history',
      ConsumptionPattern.noObservedConsumption => 'No observed consumption',
      ConsumptionPattern.adjustmentOnly => 'Adjustments only',
      ConsumptionPattern.consumptionObserved => 'Consumption observed',
      ConsumptionPattern.consumptionWithOtherChanges =>
        'Consumption with other changes',
    };

String _reasonLabel(ConsumptionReason reason) => switch (reason) {
      ConsumptionReason.consumption => 'Consumption',
      ConsumptionReason.purchase => 'Purchase',
      ConsumptionReason.stockAddition => 'Stock addition',
      ConsumptionReason.manualAdjustment => 'Manual adjustment',
      ConsumptionReason.batchAdjustment => 'Batch adjustment',
      ConsumptionReason.batchRemoval => 'Batch removal',
      ConsumptionReason.unknown => 'Inventory change',
    };

String _period(ConsumptionObservationPeriod period) {
  if (period.start == null || period.end == null) return 'Not available';
  return '${period.start!.toLocal()} — ${period.end!.toLocal()}';
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
