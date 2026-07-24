import 'package:flutter/material.dart';

import '../../inventory_update/domain/inventory_update_models.dart';
import '../application/receipt_commit_service.dart';
import '../domain/receipt_commit_models.dart';

class ReceiptCommitReviewScreen extends StatefulWidget {
  const ReceiptCommitReviewScreen({
    super.key,
    required this.service,
    required this.storeName,
    required this.input,
  });

  final ReceiptCommitService service;
  final String storeName;
  final InventoryUpdateInput input;

  @override
  State<ReceiptCommitReviewScreen> createState() =>
      _ReceiptCommitReviewScreenState();
}

class _ReceiptCommitReviewScreenState extends State<ReceiptCommitReviewScreen> {
  ReceiptCommitReview? _review;
  ReceiptCommitResult? _result;
  ReceiptCommitCancellation? _cancellation;
  Object? _error;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _review = null;
      _result = null;
      _cancellation = null;
      _error = null;
    });
    try {
      final review = await widget.service.beginReview(
        storeName: widget.storeName,
        input: widget.input,
      );
      if (!mounted) return;
      setState(() => _review = review);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _approve() async {
    final review = _review;
    if (review == null || review.plan.actions.isEmpty || _committing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve inventory updates?'),
        content: const Text(
          'Inventory will change only after this approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            key: const ValueKey('confirm-receipt-commit'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve and Commit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _committing = true);
    try {
      final approval = widget.service.approve(review);
      final result = await widget.service.commit(approval);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  void _cancel() {
    final review = _review;
    if (review == null || _committing) return;
    setState(() => _cancellation = widget.service.cancel(review));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('receipt-commit-review-screen'),
        appBar: AppBar(title: const Text('Receipt Commit Review')),
        body: _body(),
      );

  Widget _body() {
    if (_error != null) {
      return Center(
        key: const ValueKey('receipt-commit-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Receipt commit review is unavailable.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final result = _result;
    if (result != null) return _CommittedView(result: result);
    final cancellation = _cancellation;
    if (cancellation != null) {
      return Center(
        key: const ValueKey('receipt-commit-cancelled'),
        child: Text(
          'Commit cancelled\n${cancellation.cancelledAt.toIso8601String()}',
          textAlign: TextAlign.center,
        ),
      );
    }
    final review = _review;
    if (review == null) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('receipt-commit-loading'),
        ),
      );
    }
    return _ReviewBody(
      review: review,
      committing: _committing,
      onApprove: _approve,
      onCancel: _cancel,
    );
  }
}

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({
    required this.review,
    required this.committing,
    required this.onApprove,
    required this.onCancel,
  });

  final ReceiptCommitReview review;
  final bool committing;
  final VoidCallback onApprove;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final plan = review.plan;
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('receipt-commit-review-results'),
            padding: const EdgeInsets.all(12),
            children: [
              _ReviewSection(
                title: 'New Products',
                actions:
                    plan.actionsOf(InventoryUpdateActionType.addNewProduct),
                storeName: review.storeName,
              ),
              _ReviewSection(
                title: 'Quantity Updates',
                actions:
                    plan.actionsOf(InventoryUpdateActionType.increaseQuantity),
                storeName: review.storeName,
              ),
              _ReviewSection(
                title: 'Ignored Products',
                actions:
                    plan.actionsOf(InventoryUpdateActionType.ignoreDuplicate),
                storeName: review.storeName,
              ),
              _ReviewSection(
                title: 'Unknown Products',
                actions:
                    plan.actionsOf(InventoryUpdateActionType.unknownProduct),
                storeName: review.storeName,
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('cancel-receipt-commit'),
                    onPressed: committing ? null : onCancel,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('approve-receipt-commit'),
                    onPressed:
                        committing || plan.actions.isEmpty ? null : onApprove,
                    child: Text(committing ? 'Committing…' : 'Approve'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.title,
    required this.actions,
    required this.storeName,
  });

  final String title;
  final List<InventoryUpdateAction> actions;
  final String storeName;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (actions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('None'),
                ),
              for (final action in actions)
                _ReviewAction(action: action, storeName: storeName),
            ],
          ),
        ),
      );
}

class _ReviewAction extends StatelessWidget {
  const _ReviewAction({required this.action, required this.storeName});

  final InventoryUpdateAction action;
  final String storeName;

  @override
  Widget build(BuildContext context) => Card.outlined(
        key: ValueKey('receipt-commit-item-${action.receiptLineId}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field('Product Name', action.productName),
              _Field('Store', storeName),
              _Field(
                'Receipt Quantity',
                _quantity(action.trace.receiptQuantity),
              ),
              _Field(
                'Current Inventory',
                _quantity(action.trace.previousInventory?.quantity),
              ),
              _Field('New Quantity', _quantity(action.trace.newQuantity)),
              _Field('Action', _actionLabel(action.type)),
              _Field('Reason', action.trace.reason.name),
            ],
          ),
        ),
      );
}

class _CommittedView extends StatelessWidget {
  const _CommittedView({required this.result});

  final ReceiptCommitResult result;

  @override
  Widget build(BuildContext context) => Center(
        key: const ValueKey('receipt-commit-completed'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              const Text('Receipt committed'),
              Text('Committed Products: ${result.committedProducts.length}'),
              Text('Ignored Products: ${result.ignoredProducts.length}'),
              Text('Unknown Products: ${result.unknownProducts.length}'),
              Text(
                  'Commit Timestamp: ${result.commitTimestamp.toIso8601String()}'),
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
