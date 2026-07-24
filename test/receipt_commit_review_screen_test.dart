import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_commit/presentation/receipt_commit_review_screen.dart';

import 'inventory_update_test_support.dart';
import 'receipt_commit_test_support.dart';

void main() {
  testWidgets('renders grouped review details without writing inventory',
      (tester) async {
    final harness = ReceiptCommitHarness(items: [garlicInventory()]);

    await tester.pumpWidget(MaterialApp(
      home: ReceiptCommitReviewScreen(
        service: harness.service,
        storeName: 'Tamimi',
        input: mixedCommitInput(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('New Products'), findsOneWidget);
    expect(find.text('Quantity Updates'), findsOneWidget);
    expect(find.text('Product Name: ثوم'), findsOneWidget);
    expect(find.text('Store: Tamimi'), findsWidgets);
    expect(find.text('Receipt Quantity: 2'), findsOneWidget);
    expect(find.text('Current Inventory: 3'), findsOneWidget);
    expect(find.text('New Quantity: 5'), findsOneWidget);
    expect(find.text('Action: Increase Quantity'), findsOneWidget);
    expect(find.text('Reason: matchedExistingProduct'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ignored Products'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ignored Products'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Unknown Products'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Unknown Products'), findsOneWidget);
    expect(harness.inventory.items.single.quantity, 3);
  });

  testWidgets('requires confirmation before committing reviewed updates',
      (tester) async {
    final harness = ReceiptCommitHarness(items: [garlicInventory()]);
    final input = updateInput([
      receiptProduct(
        finalMatch(
          lineId: 'line-garlic',
          productId: 'catalog-garlic',
          displayName: 'ثوم',
        ),
        quantity: 2,
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: ReceiptCommitReviewScreen(
        service: harness.service,
        storeName: 'Tamimi',
        input: input,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('approve-receipt-commit')));
    await tester.pumpAndSettle();
    expect(find.text('Approve inventory updates?'), findsOneWidget);
    expect(harness.inventory.items.single.quantity, 3);

    await tester.tap(find.byKey(const ValueKey('confirm-receipt-commit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('receipt-commit-completed')),
      findsOneWidget,
    );
    expect(find.text('Committed Products: 1'), findsOneWidget);
    expect(find.textContaining('Commit Timestamp:'), findsOneWidget);
    expect(harness.inventory.items.single.quantity, 5);
  });

  testWidgets('cancel records cancellation without inventory writes',
      (tester) async {
    final harness = ReceiptCommitHarness(items: [garlicInventory()]);
    await tester.pumpWidget(MaterialApp(
      home: ReceiptCommitReviewScreen(
        service: harness.service,
        storeName: 'Tamimi',
        input: mixedCommitInput(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('cancel-receipt-commit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('receipt-commit-cancelled')),
      findsOneWidget,
    );
    expect(find.textContaining('Commit cancelled'), findsOneWidget);
    expect(harness.inventory.items.single.quantity, 3);
  });

  testWidgets('empty receipt displays sections and disables approval',
      (tester) async {
    final harness = ReceiptCommitHarness();
    await tester.pumpWidget(MaterialApp(
      home: ReceiptCommitReviewScreen(
        service: harness.service,
        storeName: 'Tamimi',
        input: updateInput(const []),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('None'), findsNWidgets(4));
    final approve = tester.widget<FilledButton>(
      find.byKey(const ValueKey('approve-receipt-commit')),
    );
    expect(approve.onPressed, isNull);
    expect(harness.inventory.items, isEmpty);
  });
}
