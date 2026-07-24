import 'package:flutter/material.dart';

import '../domain/receipt_commit_models.dart';

class ReceiptCommitDebugScreen extends StatelessWidget {
  const ReceiptCommitDebugScreen({
    super.key,
    required this.review,
    this.result,
    this.cancellation,
  });

  final ReceiptCommitReview review;
  final ReceiptCommitResult? result;
  final ReceiptCommitCancellation? cancellation;

  @override
  Widget build(BuildContext context) {
    final trace = result?.trace ?? cancellation?.trace ?? review.trace;
    return Scaffold(
      key: const ValueKey('receipt-commit-debug-screen'),
      appBar: AppBar(title: const Text('Receipt Commit Debug')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Review ID: ${review.reviewId}'),
          Text('Receipt ID: ${review.input.receiptId}'),
          Text('Store: ${review.storeName}'),
          Text('Plan Actions: ${review.plan.actions.length}'),
          const SizedBox(height: 12),
          Text('Trace', style: Theme.of(context).textTheme.titleLarge),
          for (final event in trace)
            ListTile(
              title: Text(event.type.name),
              subtitle: Text(event.timestamp.toIso8601String()),
            ),
        ],
      ),
    );
  }
}
