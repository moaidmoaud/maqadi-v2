import 'package:flutter/material.dart';

import '../application/low_stock_service.dart';
import '../domain/low_stock_failure.dart';
import '../domain/low_stock_prediction.dart';
import '../domain/low_stock_result.dart';

class LowStockScreen extends StatefulWidget {
  const LowStockScreen({
    super.key,
    required this.service,
    this.onOpenProduct,
  });

  final LowStockService service;
  final ValueChanged<String>? onOpenProduct;

  @override
  State<LowStockScreen> createState() => _LowStockScreenState();
}

class _LowStockScreenState extends State<LowStockScreen> {
  int _loadVersion = 0;
  bool _loading = true;
  List<LowStockResult> _results = const [];
  Map<String, LowStockFailure> _itemFailures = const {};
  LowStockFailure? _failure;
  _PredictionFilter _filter = _PredictionFilter.all;

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
        case LowStockEvaluationSuccess(:final results, :final failures):
          _results = results;
          _itemFailures = failures;
        case LowStockEvaluationFailure(:final failure):
          _results = const [];
          _itemFailures = const {};
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Low stock outlook'),
          actions: [
            PopupMenuButton<_PredictionFilter>(
              key: const ValueKey('low-stock-filter'),
              tooltip: 'Filter predictions',
              initialValue: _filter,
              onSelected: (value) => setState(() => _filter = value),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _PredictionFilter.all,
                  child: Text('All predictions'),
                ),
                PopupMenuItem(
                  value: _PredictionFilter.normal,
                  child: Text('Normal'),
                ),
                PopupMenuItem(
                  value: _PredictionFilter.monitor,
                  child: Text('Monitor'),
                ),
                PopupMenuItem(
                  value: _PredictionFilter.lowSoon,
                  child: Text('Low soon'),
                ),
              ],
              icon: Icon(
                _filter == _PredictionFilter.all
                    ? Icons.filter_list
                    : Icons.filter_alt,
              ),
            ),
            IconButton(
              key: const ValueKey('low-stock-refresh'),
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
        child: CircularProgressIndicator(key: ValueKey('low-stock-loading')),
      );
    }
    final failure = _failure;
    if (failure != null) {
      return _MessageState(
        key: const ValueKey('low-stock-error'),
        icon: Icons.error_outline,
        title: 'Low-stock outlook is unavailable',
        message: failure.message,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_results.isEmpty && _itemFailures.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: const _ScrollableMessage(
          key: ValueKey('low-stock-empty'),
          icon: Icons.inventory_2_outlined,
          title: 'No prediction results',
          message: 'Add inventory history before reviewing the outlook.',
        ),
      );
    }
    final visibleResults = _results
        .where((result) => _filter.includes(result.prediction.state))
        .toList(growable: false);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (visibleResults.isEmpty && _results.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No predictions match this filter.')),
            ),
          for (final result in visibleResults) ...[
            _LowStockCard(
              result: result,
              onExplanation: () => _showExplanation(result.explanation),
              onOpenProduct: widget.onOpenProduct == null
                  ? null
                  : () => widget.onOpenProduct!(result.productId),
            ),
            const SizedBox(height: 10),
          ],
          for (final entry in _itemFailures.entries) ...[
            _ProductFailureCard(productId: entry.key, failure: entry.value),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  void _showExplanation(LowStockExplanation explanation) {
    final evidence = explanation.evidence;
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
                'Prediction explanation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _DetailRow(
                  'Prediction', _predictionLabel(explanation.prediction)),
              _DetailRow('Reason', explanation.reasonCode.name),
              _DetailRow('Health', explanation.healthState.name),
              _DetailRow('Consumption', explanation.consumptionPattern.name),
              _DetailRow(
                'Current quantity',
                _number(evidence.currentQuantity),
              ),
              _DetailRow(
                'Threshold',
                evidence.lowStockThreshold == null
                    ? 'Not available'
                    : _number(evidence.lowStockThreshold!),
              ),
              _DetailRow(
                'Observed consumption',
                _number(evidence.totalObservedConsumption),
              ),
              _DetailRow(
                'Consumption events',
                '${evidence.consumptionEventCount}',
              ),
              _DetailRow(
                'Observation days',
                evidence.observationDurationDays == null
                    ? 'Not available'
                    : _number(evidence.observationDurationDays!),
              ),
              _DetailRow(
                'Daily consumption',
                evidence.dailyConsumption == null
                    ? 'Not calculated'
                    : _number(evidence.dailyConsumption!),
              ),
              _DetailRow(
                'Prediction horizon',
                '${evidence.predictionHorizonDays} days',
              ),
              _DetailRow(
                'Projected quantity',
                evidence.projectedQuantity == null
                    ? 'Not calculated'
                    : _number(evidence.projectedQuantity!),
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

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({
    required this.result,
    required this.onExplanation,
    required this.onOpenProduct,
  });

  final LowStockResult result;
  final VoidCallback onExplanation;
  final VoidCallback? onOpenProduct;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey('low-stock-product-${result.productId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.productName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(result.category),
                    Text(result.explanation.summary ?? ''),
                  ],
                ),
              ),
              Column(
                children: [
                  _PredictionBadge(state: result.prediction.state),
                  TextButton(
                    key: ValueKey('low-stock-explanation-${result.productId}'),
                    onPressed: onExplanation,
                    child: const Text('Why?'),
                  ),
                  if (onOpenProduct != null)
                    TextButton(
                      key: ValueKey(
                        'low-stock-open-product-${result.productId}',
                      ),
                      onPressed: onOpenProduct,
                      child: const Text('Open'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _PredictionBadge extends StatelessWidget {
  const _PredictionBadge({required this.state});

  final LowStockPredictionState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      LowStockPredictionState.normal => Colors.green,
      LowStockPredictionState.monitor => Colors.orange,
      LowStockPredictionState.lowSoon => Colors.red,
    };
    return Chip(
      key: ValueKey('low-stock-state-${state.name}'),
      label: Text(_predictionLabel(state)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color),
    );
  }
}

class _ProductFailureCard extends StatelessWidget {
  const _ProductFailureCard({required this.productId, required this.failure});

  final String productId;
  final LowStockFailure failure;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey('low-stock-product-failure-$productId'),
        child: ListTile(
          leading: const Icon(Icons.warning_amber_outlined),
          title: Text(productId),
          subtitle: Text(failure.message),
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
            SizedBox(width: 150, child: Text(label)),
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

String _predictionLabel(LowStockPredictionState state) => switch (state) {
      LowStockPredictionState.normal => 'Normal',
      LowStockPredictionState.monitor => 'Monitor',
      LowStockPredictionState.lowSoon => 'Low soon',
    };

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

enum _PredictionFilter {
  all,
  normal,
  monitor,
  lowSoon;

  bool includes(LowStockPredictionState state) => switch (this) {
        _PredictionFilter.all => true,
        _PredictionFilter.normal => state == LowStockPredictionState.normal,
        _PredictionFilter.monitor => state == LowStockPredictionState.monitor,
        _PredictionFilter.lowSoon => state == LowStockPredictionState.lowSoon,
      };
}
