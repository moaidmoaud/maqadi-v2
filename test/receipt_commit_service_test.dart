import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/inventory_update/domain/inventory_update_models.dart';
import 'package:maqadi_v2/receipt_commit/domain/receipt_commit_models.dart';

import 'inventory_update_test_support.dart';
import 'receipt_commit_test_support.dart';

void main() {
  test('review is read-only and commit requires a one-time approval', () async {
    final harness = ReceiptCommitHarness(items: [garlicInventory()]);
    final review = await harness.service.beginReview(
      storeName: 'Tamimi',
      input: updateInput([
        receiptProduct(
          finalMatch(
            lineId: 'line-garlic',
            productId: 'catalog-garlic',
            displayName: 'ثوم',
          ),
          quantity: 2,
        ),
      ]),
    );

    expect(harness.inventory.items.single.quantity, 3);
    expect(
      review.trace.map((event) => event.type),
      [ReceiptCommitEventType.reviewStarted],
    );

    final approval = harness.service.approve(review);
    expect(harness.inventory.items.single.quantity, 3);
    expect(
      approval.trace.map((event) => event.type),
      [
        ReceiptCommitEventType.reviewStarted,
        ReceiptCommitEventType.reviewCompleted,
        ReceiptCommitEventType.commitApproved,
      ],
    );

    final result = await harness.service.commit(approval);
    expect(harness.inventory.items.single.quantity, 5);
    expect(result.committedProducts.single.productName, 'ثوم');
    expect(result.ignoredProducts, isEmpty);
    expect(result.unknownProducts, isEmpty);
    expect(result.commitTimestamp, DateTime.utc(2026, 7, 24, 9, 0, 3));

    await expectLater(
      harness.service.commit(approval),
      throwsA(
        isA<ReceiptCommitException>().having(
          (error) => error.code,
          'code',
          ReceiptCommitFailureCode.approvalAlreadyUsed,
        ),
      ),
    );
  });

  test('cancellation records trace and never writes inventory', () async {
    final harness = ReceiptCommitHarness(items: [garlicInventory()]);
    final review = await harness.service.beginReview(
      storeName: 'Tamimi',
      input: mixedCommitInput(),
    );

    final cancellation = harness.service.cancel(review);

    expect(harness.inventory.items.single.quantity, 3);
    expect(
      cancellation.trace.last.type,
      ReceiptCommitEventType.commitCancelled,
    );
    expect(
      ReceiptCommitCancellation.fromJson(cancellation.toJson()).toJson(),
      cancellation.toJson(),
    );
  });

  test('changed inventory invalidates the reviewed plan', () async {
    final harness = ReceiptCommitHarness(items: [garlicInventory()]);
    final review = await harness.service.beginReview(
      storeName: 'Tamimi',
      input: mixedCommitInput(),
    );
    final approval = harness.service.approve(review);
    harness.inventory.changeQuantity(harness.inventory.items.single, 1);

    await expectLater(
      harness.service.commit(approval),
      throwsA(
        isA<ReceiptCommitException>().having(
          (error) => error.code,
          'code',
          ReceiptCommitFailureCode.planChanged,
        ),
      ),
    );
    expect(harness.inventory.items.single.quantity, 4);
  });

  test('review and immutable commit result serialize stably', () async {
    final harness = ReceiptCommitHarness(items: [garlicInventory()]);
    final review = await harness.service.beginReview(
      storeName: 'Tamimi',
      input: mixedCommitInput(),
    );
    final result = await harness.service.commit(
      harness.service.approve(review),
    );

    expect(
      ReceiptCommitReview.fromJson(review.toJson()).toJson(),
      review.toJson(),
    );
    expect(
      ReceiptCommitResult.fromJson(result.toJson()).toJson(),
      result.toJson(),
    );
    expect(result.committedProducts, hasLength(2));
    expect(result.ignoredProducts, hasLength(1));
    expect(result.unknownProducts, hasLength(1));
  });

  test('empty receipt creates a review but cannot mutate inventory', () async {
    final harness = ReceiptCommitHarness();
    final review = await harness.service.beginReview(
      storeName: 'Tamimi',
      input: updateInput(const <MatchedReceiptProduct>[]),
    );

    expect(review.plan.actions, isEmpty);
    expect(harness.inventory.items, isEmpty);
  });
}
