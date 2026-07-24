import 'dart:convert';

import '../../inventory_update/application/inventory_update_service.dart';
import '../../inventory_update/domain/inventory_update_models.dart';
import '../domain/receipt_commit_models.dart';

typedef ReceiptCommitClock = DateTime Function();
typedef ReceiptCommitIdFactory = String Function();

class ReceiptCommitService {
  ReceiptCommitService({
    required InventoryUpdateService inventoryUpdateService,
    ReceiptCommitClock? clock,
    ReceiptCommitIdFactory? idFactory,
  })  : _inventoryUpdateService = inventoryUpdateService,
        _clock = clock ?? DateTime.now,
        _idFactory = idFactory;

  final InventoryUpdateService _inventoryUpdateService;
  final ReceiptCommitClock _clock;
  final ReceiptCommitIdFactory? _idFactory;
  final Map<String, String> _approvedTokens = {};
  int _idCounter = 0;

  Future<ReceiptCommitReview> beginReview({
    required String storeName,
    required InventoryUpdateInput input,
  }) async {
    final cleanStore = storeName.trim();
    if (cleanStore.isEmpty) {
      throw const ReceiptCommitException(
        ReceiptCommitFailureCode.invalidStore,
        'Store is required before receipt review.',
      );
    }
    final started = ReceiptCommitTraceEvent(
      type: ReceiptCommitEventType.reviewStarted,
      timestamp: _clock(),
    );
    final plan = await _inventoryUpdateService.createPlan(input);
    return ReceiptCommitReview(
      reviewId: _newId(),
      storeName: cleanStore,
      input: input,
      plan: plan,
      trace: [started],
    );
  }

  ReceiptCommitApproval approve(ReceiptCommitReview review) {
    _validateReview(review);
    final token = _newId();
    _approvedTokens[token] = review.reviewId;
    return ReceiptCommitApproval(
      token: token,
      review: review,
      trace: [
        ...review.trace,
        ReceiptCommitTraceEvent(
          type: ReceiptCommitEventType.reviewCompleted,
          timestamp: _clock(),
        ),
        ReceiptCommitTraceEvent(
          type: ReceiptCommitEventType.commitApproved,
          timestamp: _clock(),
        ),
      ],
    );
  }

  Future<ReceiptCommitResult> commit(ReceiptCommitApproval approval) async {
    final reviewId = _approvedTokens.remove(approval.token);
    if (reviewId == null) {
      throw const ReceiptCommitException(
        ReceiptCommitFailureCode.approvalAlreadyUsed,
        'A valid unused approval is required.',
      );
    }
    if (reviewId != approval.review.reviewId) {
      throw const ReceiptCommitException(
        ReceiptCommitFailureCode.approvalRequired,
        'Approval does not belong to this review.',
      );
    }
    final currentPlan =
        await _inventoryUpdateService.createPlan(approval.review.input);
    if (jsonEncode(currentPlan.toJson()) !=
        jsonEncode(approval.review.plan.toJson())) {
      throw const ReceiptCommitException(
        ReceiptCommitFailureCode.planChanged,
        'Inventory changed after review. Start a new review.',
      );
    }

    await _inventoryUpdateService.apply(approval.review.input);
    final committed = approval.review.plan.actions
        .where(
          (action) =>
              action.type == InventoryUpdateActionType.addNewProduct ||
              action.type == InventoryUpdateActionType.increaseQuantity,
        )
        .map(_commitProduct);
    final ignored = approval.review.plan
        .actionsOf(InventoryUpdateActionType.ignoreDuplicate)
        .map(_commitProduct);
    final unknown = approval.review.plan
        .actionsOf(InventoryUpdateActionType.unknownProduct)
        .map(_commitProduct);
    return ReceiptCommitResult(
      receiptId: approval.review.input.receiptId,
      storeName: approval.review.storeName,
      committedProducts: committed,
      ignoredProducts: ignored,
      unknownProducts: unknown,
      commitTimestamp: _clock(),
      trace: approval.trace,
    );
  }

  ReceiptCommitCancellation cancel(ReceiptCommitReview review) {
    _validateReview(review);
    _approvedTokens.removeWhere((_, reviewId) => reviewId == review.reviewId);
    final reviewCompletedAt = _clock();
    final cancelledAt = _clock();
    return ReceiptCommitCancellation(
      receiptId: review.input.receiptId,
      cancelledAt: cancelledAt,
      trace: [
        ...review.trace,
        ReceiptCommitTraceEvent(
          type: ReceiptCommitEventType.reviewCompleted,
          timestamp: reviewCompletedAt,
        ),
        ReceiptCommitTraceEvent(
          type: ReceiptCommitEventType.commitCancelled,
          timestamp: cancelledAt,
        ),
      ],
    );
  }

  ReceiptCommitProduct _commitProduct(InventoryUpdateAction action) =>
      ReceiptCommitProduct(
        receiptLineId: action.receiptLineId,
        productName: action.productName,
        action: action.type,
      );

  void _validateReview(ReceiptCommitReview review) {
    if (review.reviewId.trim().isEmpty ||
        review.storeName.trim().isEmpty ||
        review.plan.receiptId != review.input.receiptId ||
        review.trace.length != 1 ||
        review.trace.single.type != ReceiptCommitEventType.reviewStarted) {
      throw const ReceiptCommitException(
        ReceiptCommitFailureCode.invalidReview,
        'Receipt review is invalid.',
      );
    }
  }

  String _newId() =>
      _idFactory?.call() ??
      '${_clock().microsecondsSinceEpoch}-${++_idCounter}';
}
