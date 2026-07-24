import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_commit/presentation/receipt_commit_debug_screen.dart';

import 'receipt_commit_test_support.dart';

void main() {
  testWidgets('debug screen renders the immutable commit trace',
      (tester) async {
    final harness = ReceiptCommitHarness(items: [garlicInventory()]);
    final review = await harness.service.beginReview(
      storeName: 'Tamimi',
      input: mixedCommitInput(),
    );
    final cancellation = harness.service.cancel(review);

    await tester.pumpWidget(MaterialApp(
      home: ReceiptCommitDebugScreen(
        review: review,
        cancellation: cancellation,
      ),
    ));

    expect(
      find.byKey(const ValueKey('receipt-commit-debug-screen')),
      findsOneWidget,
    );
    expect(find.text('Store: Tamimi'), findsOneWidget);
    expect(find.text('reviewStarted'), findsOneWidget);
    expect(find.text('reviewCompleted'), findsOneWidget);
    expect(find.text('commitCancelled'), findsOneWidget);
  });
}
