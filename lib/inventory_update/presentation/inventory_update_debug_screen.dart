import 'package:flutter/material.dart';

import '../application/inventory_update_service.dart';
import '../domain/inventory_update_models.dart';

class InventoryUpdateDebugScreen extends StatefulWidget {
  const InventoryUpdateDebugScreen({
    super.key,
    required this.service,
    required this.input,
  });

  final InventoryUpdateService service;
  final InventoryUpdateInput input;

  @override
  State<InventoryUpdateDebugScreen> createState() =>
      _InventoryUpdateDebugScreenState();
}

class _InventoryUpdateDebugScreenState
    extends State<InventoryUpdateDebugScreen> {
  InventoryUpdatePlan? _plan;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _plan = null;
      _error = null;
    });
    try {
      final plan = await widget.service.createPlan(widget.input);
      if (!mounted) return;
      setState(() => _plan = plan);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('inventory-update-debug-screen'),
        appBar: AppBar(title: const Text('Inventory Update Debug')),
        body: _body(),
      );

  Widget _body() {
    if (_error != null) {
      return Center(
        key: const ValueKey('inventory-update-debug-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Inventory update plan is unavailable.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final plan = _plan;
    if (plan == null) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('inventory-update-debug-loading'),
        ),
      );
    }
    if (plan.actions.isEmpty) {
      return const Center(
        key: ValueKey('inventory-update-debug-empty'),
        child: Text('No matched receipt products.'),
      );
    }
    return ListView(
      key: const ValueKey('inventory-update-debug-results'),
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Inventory Result',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                _Field('Products Added', '${plan.productsAdded}'),
                _Field('Products Updated', '${plan.productsUpdated}'),
                _Field('Products Ignored', '${plan.productsIgnored}'),
                _Field('Unknown Products', '${plan.unknownProducts}'),
              ],
            ),
          ),
        ),
        for (final action in plan.actions) _ActionCard(action: action),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});

  final InventoryUpdateAction action;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey('inventory-update-action-${action.receiptLineId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.productName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _Field(
                'Previous Quantity',
                _quantity(action.trace.previousInventory?.quantity),
              ),
              _Field(
                'Receipt Quantity',
                _quantity(action.trace.receiptQuantity),
              ),
              _Field('New Quantity', _quantity(action.trace.newQuantity)),
              _Field('Action', _actionLabel(action.type)),
              _Field('Update Reason', action.trace.reason.name),
            ],
          ),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('$label: $value'),
      );
}

String _quantity(double? value) {
  if (value == null) return 'Not available';
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

String _actionLabel(InventoryUpdateActionType type) => switch (type) {
      InventoryUpdateActionType.addNewProduct => 'Add New Product',
      InventoryUpdateActionType.increaseQuantity => 'Increase Quantity',
      InventoryUpdateActionType.ignoreDuplicate => 'Ignore Duplicate',
      InventoryUpdateActionType.unknownProduct => 'Unknown Product',
    };
