import 'package:flutter/material.dart';

import '../application/shopping_recommendation_service.dart';
import '../domain/shopping_recommendation.dart';
import '../domain/shopping_recommendation_explanation.dart';
import '../domain/shopping_recommendation_failure.dart';
import '../domain/shopping_recommendation_result.dart';

class ShoppingRecommendationScreen extends StatefulWidget {
  const ShoppingRecommendationScreen({
    super.key,
    required this.service,
    this.onOpenProduct,
  });

  final ShoppingRecommendationService service;
  final ValueChanged<String>? onOpenProduct;

  @override
  State<ShoppingRecommendationScreen> createState() =>
      _ShoppingRecommendationScreenState();
}

class _ShoppingRecommendationScreenState
    extends State<ShoppingRecommendationScreen> {
  int _loadVersion = 0;
  bool _loading = true;
  List<ShoppingRecommendationResult> _results = const [];
  Map<String, ShoppingRecommendationFailure> _itemFailures = const {};
  ShoppingRecommendationFailure? _failure;
  _RecommendationFilter _filter = _RecommendationFilter.all;

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
        case ShoppingRecommendationEvaluationSuccess(
            :final results,
            :final failures,
          ):
          _results = results;
          _itemFailures = failures;
        case ShoppingRecommendationEvaluationFailure(:final failure):
          _results = const [];
          _itemFailures = const {};
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Shopping recommendations'),
          actions: [
            PopupMenuButton<_RecommendationFilter>(
              key: const ValueKey('recommendation-filter'),
              tooltip: 'Filter recommendations',
              initialValue: _filter,
              onSelected: (value) => setState(() => _filter = value),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _RecommendationFilter.all,
                  child: Text('All recommendations'),
                ),
                PopupMenuItem(
                  value: _RecommendationFilter.ignore,
                  child: Text('Ignore'),
                ),
                PopupMenuItem(
                  value: _RecommendationFilter.watch,
                  child: Text('Watch'),
                ),
                PopupMenuItem(
                  value: _RecommendationFilter.buySoon,
                  child: Text('Buy soon'),
                ),
                PopupMenuItem(
                  value: _RecommendationFilter.buyNow,
                  child: Text('Buy now'),
                ),
              ],
              icon: Icon(
                _filter == _RecommendationFilter.all
                    ? Icons.filter_list
                    : Icons.filter_alt,
              ),
            ),
            IconButton(
              key: const ValueKey('recommendation-refresh'),
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
        child: CircularProgressIndicator(
          key: ValueKey('recommendation-loading'),
        ),
      );
    }
    final failure = _failure;
    if (failure != null) {
      return _MessageState(
        key: const ValueKey('recommendation-error'),
        icon: Icons.error_outline,
        title: 'Recommendations are unavailable',
        message: failure.message,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_results.isEmpty && _itemFailures.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: const _ScrollableMessage(
          key: ValueKey('recommendation-empty'),
          icon: Icons.recommend_outlined,
          title: 'No recommendation results',
          message: 'Add inventory history before reviewing recommendations.',
        ),
      );
    }
    final visibleResults = _results
        .where((result) => _filter.includes(result.recommendation.state))
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
              child: Center(
                child: Text('No recommendations match this filter.'),
              ),
            ),
          for (final result in visibleResults) ...[
            _RecommendationCard(
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

  void _showExplanation(ShoppingRecommendationExplanation explanation) {
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
                'Recommendation explanation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _DetailRow(
                'Recommendation',
                _recommendationLabel(explanation.recommendation),
              ),
              _DetailRow('Reason', explanation.reasonCode.name),
              _DetailRow('Health', explanation.healthState.name),
              _DetailRow(
                'Consumption pattern',
                explanation.consumptionPattern.name,
              ),
              _DetailRow(
                'Consumption summary',
                explanation.consumptionSummary ?? 'Not available',
              ),
              _DetailRow('Prediction', explanation.lowStockPrediction.name),
              _DetailRow('Current quantity', _number(evidence.currentQuantity)),
              _DetailRow('Unit', evidence.unit),
              _DetailRow(
                'Observed consumption',
                _number(evidence.totalObservedConsumption),
              ),
              _DetailRow(
                'Consumption events',
                '${evidence.consumptionEventCount}',
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

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.result,
    required this.onExplanation,
    required this.onOpenProduct,
  });

  final ShoppingRecommendationResult result;
  final VoidCallback onExplanation;
  final VoidCallback? onOpenProduct;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey('recommendation-product-${result.productId}'),
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
                  _RecommendationBadge(state: result.recommendation.state),
                  TextButton(
                    key: ValueKey(
                      'recommendation-explanation-${result.productId}',
                    ),
                    onPressed: onExplanation,
                    child: const Text('Why?'),
                  ),
                  if (onOpenProduct != null)
                    TextButton(
                      key: ValueKey(
                        'recommendation-open-product-${result.productId}',
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

class _RecommendationBadge extends StatelessWidget {
  const _RecommendationBadge({required this.state});

  final ShoppingRecommendationState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      ShoppingRecommendationState.ignore => Colors.green,
      ShoppingRecommendationState.watch => Colors.blue,
      ShoppingRecommendationState.buySoon => Colors.orange,
      ShoppingRecommendationState.buyNow => Colors.red,
    };
    return Chip(
      key: ValueKey('recommendation-state-${state.name}'),
      label: Text(_recommendationLabel(state)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color),
    );
  }
}

class _ProductFailureCard extends StatelessWidget {
  const _ProductFailureCard({required this.productId, required this.failure});

  final String productId;
  final ShoppingRecommendationFailure failure;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey('recommendation-product-failure-$productId'),
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

enum _RecommendationFilter {
  all,
  ignore,
  watch,
  buySoon,
  buyNow;

  bool includes(ShoppingRecommendationState state) => switch (this) {
        _RecommendationFilter.all => true,
        _RecommendationFilter.ignore =>
          state == ShoppingRecommendationState.ignore,
        _RecommendationFilter.watch =>
          state == ShoppingRecommendationState.watch,
        _RecommendationFilter.buySoon =>
          state == ShoppingRecommendationState.buySoon,
        _RecommendationFilter.buyNow =>
          state == ShoppingRecommendationState.buyNow,
      };
}

String _recommendationLabel(ShoppingRecommendationState state) =>
    switch (state) {
      ShoppingRecommendationState.ignore => 'Ignore',
      ShoppingRecommendationState.watch => 'Watch',
      ShoppingRecommendationState.buySoon => 'Buy soon',
      ShoppingRecommendationState.buyNow => 'Buy now',
    };

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
