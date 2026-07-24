import '../../inventory_update/domain/inventory_update_models.dart';

enum ReceiptCommitEventType {
  reviewStarted,
  reviewCompleted,
  commitApproved,
  commitCancelled,
}

enum ReceiptCommitFailureCode {
  invalidStore,
  invalidReview,
  approvalRequired,
  approvalAlreadyUsed,
  planChanged,
}

class ReceiptCommitException implements Exception {
  const ReceiptCommitException(this.code, this.message);

  final ReceiptCommitFailureCode code;
  final String message;

  @override
  String toString() => 'ReceiptCommitException(${code.name}, $message)';
}

class ReceiptCommitTraceEvent {
  const ReceiptCommitTraceEvent({
    required this.type,
    required this.timestamp,
  });

  factory ReceiptCommitTraceEvent.fromJson(Map<String, Object?> json) =>
      ReceiptCommitTraceEvent(
        type: ReceiptCommitEventType.values.byName(json['type']! as String),
        timestamp: DateTime.parse(json['timestamp']! as String),
      );

  final ReceiptCommitEventType type;
  final DateTime timestamp;

  Map<String, Object> toJson() => {
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
      };
}

class ReceiptCommitReview {
  ReceiptCommitReview({
    required this.reviewId,
    required this.storeName,
    required this.input,
    required this.plan,
    required Iterable<ReceiptCommitTraceEvent> trace,
  }) : trace = List.unmodifiable(trace);

  factory ReceiptCommitReview.fromJson(Map<String, Object?> json) =>
      ReceiptCommitReview(
        reviewId: json['reviewId']! as String,
        storeName: json['storeName']! as String,
        input: InventoryUpdateInput.fromJson(
          json['input']! as Map<String, Object?>,
        ),
        plan: InventoryUpdatePlan.fromJson(
          json['plan']! as Map<String, Object?>,
        ),
        trace: (json['trace']! as List<Object?>).map(
          (value) => ReceiptCommitTraceEvent.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );

  final String reviewId;
  final String storeName;
  final InventoryUpdateInput input;
  final InventoryUpdatePlan plan;
  final List<ReceiptCommitTraceEvent> trace;

  Map<String, Object> toJson() => {
        'reviewId': reviewId,
        'storeName': storeName,
        'input': input.toJson(),
        'plan': plan.toJson(),
        'trace': [for (final event in trace) event.toJson()],
      };
}

class ReceiptCommitApproval {
  ReceiptCommitApproval({
    required this.token,
    required this.review,
    required Iterable<ReceiptCommitTraceEvent> trace,
  }) : trace = List.unmodifiable(trace);

  final String token;
  final ReceiptCommitReview review;
  final List<ReceiptCommitTraceEvent> trace;
}

class ReceiptCommitProduct {
  const ReceiptCommitProduct({
    required this.receiptLineId,
    required this.productName,
    required this.action,
  });

  factory ReceiptCommitProduct.fromJson(Map<String, Object?> json) =>
      ReceiptCommitProduct(
        receiptLineId: json['receiptLineId']! as String,
        productName: json['productName']! as String,
        action:
            InventoryUpdateActionType.values.byName(json['action']! as String),
      );

  final String receiptLineId;
  final String productName;
  final InventoryUpdateActionType action;

  Map<String, Object> toJson() => {
        'receiptLineId': receiptLineId,
        'productName': productName,
        'action': action.name,
      };
}

class ReceiptCommitResult {
  ReceiptCommitResult({
    required this.receiptId,
    required this.storeName,
    required Iterable<ReceiptCommitProduct> committedProducts,
    required Iterable<ReceiptCommitProduct> ignoredProducts,
    required Iterable<ReceiptCommitProduct> unknownProducts,
    required this.commitTimestamp,
    required Iterable<ReceiptCommitTraceEvent> trace,
  })  : committedProducts = List.unmodifiable(committedProducts),
        ignoredProducts = List.unmodifiable(ignoredProducts),
        unknownProducts = List.unmodifiable(unknownProducts),
        trace = List.unmodifiable(trace);

  factory ReceiptCommitResult.fromJson(Map<String, Object?> json) =>
      ReceiptCommitResult(
        receiptId: json['receiptId']! as String,
        storeName: json['storeName']! as String,
        committedProducts: _productsFromJson(json['committedProducts']),
        ignoredProducts: _productsFromJson(json['ignoredProducts']),
        unknownProducts: _productsFromJson(json['unknownProducts']),
        commitTimestamp: DateTime.parse(json['commitTimestamp']! as String),
        trace: (json['trace']! as List<Object?>).map(
          (value) => ReceiptCommitTraceEvent.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );

  final String receiptId;
  final String storeName;
  final List<ReceiptCommitProduct> committedProducts;
  final List<ReceiptCommitProduct> ignoredProducts;
  final List<ReceiptCommitProduct> unknownProducts;
  final DateTime commitTimestamp;
  final List<ReceiptCommitTraceEvent> trace;

  Map<String, Object> toJson() => {
        'receiptId': receiptId,
        'storeName': storeName,
        'committedProducts': [
          for (final product in committedProducts) product.toJson(),
        ],
        'ignoredProducts': [
          for (final product in ignoredProducts) product.toJson(),
        ],
        'unknownProducts': [
          for (final product in unknownProducts) product.toJson(),
        ],
        'commitTimestamp': commitTimestamp.toIso8601String(),
        'trace': [for (final event in trace) event.toJson()],
      };
}

class ReceiptCommitCancellation {
  ReceiptCommitCancellation({
    required this.receiptId,
    required this.cancelledAt,
    required Iterable<ReceiptCommitTraceEvent> trace,
  }) : trace = List.unmodifiable(trace);

  factory ReceiptCommitCancellation.fromJson(Map<String, Object?> json) =>
      ReceiptCommitCancellation(
        receiptId: json['receiptId']! as String,
        cancelledAt: DateTime.parse(json['cancelledAt']! as String),
        trace: (json['trace']! as List<Object?>).map(
          (value) => ReceiptCommitTraceEvent.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );

  final String receiptId;
  final DateTime cancelledAt;
  final List<ReceiptCommitTraceEvent> trace;

  Map<String, Object> toJson() => {
        'receiptId': receiptId,
        'cancelledAt': cancelledAt.toIso8601String(),
        'trace': [for (final event in trace) event.toJson()],
      };
}

Iterable<ReceiptCommitProduct> _productsFromJson(Object? value) =>
    (value! as List<Object?>).map(
      (item) => ReceiptCommitProduct.fromJson(
        item! as Map<String, Object?>,
      ),
    );
