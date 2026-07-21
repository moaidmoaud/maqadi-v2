import 'package:flutter/material.dart';

import '../application/inventory_health_service.dart';
import '../domain/inventory_health_failure.dart';
import '../domain/inventory_health_result.dart';

typedef InventoryHealthProductOpener = Future<void> Function(String productId);

class InventoryHealthScreen extends StatefulWidget {
  const InventoryHealthScreen({
    super.key,
    required this.service,
    required this.onOpenProduct,
  });

  final InventoryHealthService service;
  final InventoryHealthProductOpener onOpenProduct;

  @override
  State<InventoryHealthScreen> createState() => _InventoryHealthScreenState();
}

class _InventoryHealthScreenState extends State<InventoryHealthScreen> {
  int _loadVersion = 0;
  bool _loading = true;
  List<InventoryHealthResult> _results = const [];
  InventoryHealthFailure? _failure;
  InventoryHealthStatus? _filter;

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
        case InventoryHealthEvaluationSuccess(:final results):
          _results = results;
        case InventoryHealthEvaluationFailure(:final failure):
          _results = const [];
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory health'),
        actions: [
          IconButton(
            key: const ValueKey('inventory-health-refresh'),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('inventory-health-loading'),
        ),
      );
    }
    final failure = _failure;
    if (failure != null) {
      return _MessageState(
        key: const ValueKey('inventory-health-error'),
        icon: Icons.error_outline,
        title: 'Health data is unavailable',
        message: failure.message,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }
    if (_results.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: const _ScrollableMessage(
          key: ValueKey('inventory-health-empty'),
          icon: Icons.inventory_2_outlined,
          title: 'No inventory items',
          message: 'Add a product to see its current health.',
        ),
      );
    }

    final visible = _filter == null
        ? _results
        : _results.where((result) => result.status == _filter).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _StatusFilters(
            selected: _filter,
            onSelected: (status) => setState(() => _filter = status),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: _MessageState(
                icon: Icons.filter_alt_off_outlined,
                title: 'No results',
                message: 'No products have the selected health state.',
              ),
            )
          else
            for (final result in visible) ...[
              _InventoryHealthCard(
                result: result,
                onTap: () async {
                  await widget.onOpenProduct(result.productId);
                  await _load();
                },
                onExplanation: () => _showExplanation(result.explanation),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  void _showExplanation(InventoryHealthExplanation explanation) {
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
                'Health explanation',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _ExplanationRow('Status', _statusLabel(explanation.status)),
              _ExplanationRow('Reason', explanation.reasonCode.name),
              _ExplanationRow(
                'Quantity',
                '${_number(explanation.quantity)} ${explanation.unit}',
              ),
              _ExplanationRow(
                'Threshold',
                explanation.threshold == null
                    ? 'Not available'
                    : '${_number(explanation.threshold!)} ${explanation.unit}',
              ),
              _ExplanationRow(
                  'Evaluated', explanation.timestamp.toLocal().toString()),
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

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({required this.selected, required this.onSelected});

  final InventoryHealthStatus? selected;
  final ValueChanged<InventoryHealthStatus?> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
            for (final status in const [
              InventoryHealthStatus.outOfStock,
              InventoryHealthStatus.lowStock,
              InventoryHealthStatus.unknown,
              InventoryHealthStatus.healthy,
            ]) ...[
              const SizedBox(width: 8),
              ChoiceChip(
                key: ValueKey('inventory-health-filter-${status.name}'),
                label: Text(_statusLabel(status)),
                selected: selected == status,
                onSelected: (_) => onSelected(status),
              ),
            ],
          ],
        ),
      );
}

class _InventoryHealthCard extends StatelessWidget {
  const _InventoryHealthCard({
    required this.result,
    required this.onTap,
    required this.onExplanation,
  });

  final InventoryHealthResult result;
  final VoidCallback onTap;
  final VoidCallback onExplanation;

  @override
  Widget build(BuildContext context) {
    final explanation = result.explanation;
    return Card(
      child: InkWell(
        key: ValueKey('inventory-health-product-${result.productId}'),
        onTap: onTap,
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
                    const SizedBox(height: 8),
                    Text(
                      '${_number(explanation.quantity)} ${explanation.unit}',
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _HealthBadge(status: result.status),
                  TextButton(
                    key: ValueKey(
                      'inventory-health-explanation-${result.productId}',
                    ),
                    onPressed: onExplanation,
                    child: const Text('Why?'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthBadge extends StatelessWidget {
  const _HealthBadge({required this.status});

  final InventoryHealthStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      InventoryHealthStatus.healthy => Colors.green,
      InventoryHealthStatus.lowStock => Colors.orange,
      InventoryHealthStatus.outOfStock => Colors.red,
      InventoryHealthStatus.unknown => Colors.blueGrey,
    };
    return Chip(
      key: ValueKey('inventory-health-status-${status.name}'),
      label: Text(_statusLabel(status)),
      side: BorderSide(color: color),
      backgroundColor: color.withValues(alpha: 0.12),
    );
  }
}

class _ExplanationRow extends StatelessWidget {
  const _ExplanationRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 92, child: Text(label)),
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

String _statusLabel(InventoryHealthStatus status) => switch (status) {
      InventoryHealthStatus.unknown => 'Unknown',
      InventoryHealthStatus.healthy => 'Healthy',
      InventoryHealthStatus.lowStock => 'Low stock',
      InventoryHealthStatus.outOfStock => 'Out of stock',
    };

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
