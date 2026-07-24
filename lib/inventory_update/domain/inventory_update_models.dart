import '../../product_matching_v2/domain/product_match_result.dart';

enum InventoryUpdateActionType {
  addNewProduct,
  increaseQuantity,
  ignoreDuplicate,
  unknownProduct,
}

enum InventoryUpdateReason {
  matchedProductNotInInventory,
  matchedExistingProduct,
  duplicateReceiptLine,
  productNotMatched,
  invalidReceiptQuantity,
}

class MatchedReceiptProduct {
  const MatchedReceiptProduct({
    required this.matchResult,
    required this.quantity,
  });

  factory MatchedReceiptProduct.fromJson(Map<String, Object?> json) =>
      MatchedReceiptProduct(
        matchResult: ProductMatchResult.fromJson(
          json['matchResult']! as Map<String, Object?>,
        ),
        quantity: (json['quantity']! as num).toDouble(),
      );

  final ProductMatchResult matchResult;
  final double quantity;

  Map<String, Object?> toJson() => {
        'matchResult': matchResult.toJson(),
        'quantity': quantity,
      };
}

class InventoryUpdateInput {
  InventoryUpdateInput({
    required this.receiptId,
    required this.receivedAt,
    required Iterable<MatchedReceiptProduct> products,
  }) : products = List.unmodifiable(products);

  factory InventoryUpdateInput.fromJson(Map<String, Object?> json) =>
      InventoryUpdateInput(
        receiptId: json['receiptId']! as String,
        receivedAt: DateTime.parse(json['receivedAt']! as String),
        products: (json['products']! as List<Object?>).map(
          (value) => MatchedReceiptProduct.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );

  final String receiptId;
  final DateTime receivedAt;
  final List<MatchedReceiptProduct> products;

  Map<String, Object> toJson() => {
        'receiptId': receiptId,
        'receivedAt': receivedAt.toIso8601String(),
        'products': [for (final product in products) product.toJson()],
      };
}

class InventoryProductSnapshot {
  const InventoryProductSnapshot({
    required this.productId,
    required this.displayName,
    required this.quantity,
  });

  factory InventoryProductSnapshot.fromJson(Map<String, Object?> json) =>
      InventoryProductSnapshot(
        productId: json['productId'] as String?,
        displayName: json['displayName']! as String,
        quantity: (json['quantity']! as num).toDouble(),
      );

  final String? productId;
  final String displayName;
  final double quantity;

  Map<String, Object?> toJson() => {
        'productId': productId,
        'displayName': displayName,
        'quantity': quantity,
      };
}

class InventoryUpdateTrace {
  const InventoryUpdateTrace({
    required this.previousInventory,
    required this.receiptQuantity,
    required this.newQuantity,
    required this.reason,
  });

  factory InventoryUpdateTrace.fromJson(Map<String, Object?> json) =>
      InventoryUpdateTrace(
        previousInventory: json['previousInventory'] == null
            ? null
            : InventoryProductSnapshot.fromJson(
                json['previousInventory']! as Map<String, Object?>,
              ),
        receiptQuantity: (json['receiptQuantity']! as num).toDouble(),
        newQuantity: (json['newQuantity'] as num?)?.toDouble(),
        reason: InventoryUpdateReason.values.byName(json['reason']! as String),
      );

  final InventoryProductSnapshot? previousInventory;
  final double receiptQuantity;
  final double? newQuantity;
  final InventoryUpdateReason reason;

  Map<String, Object?> toJson() => {
        'previousInventory': previousInventory?.toJson(),
        'receiptQuantity': receiptQuantity,
        'newQuantity': newQuantity,
        'reason': reason.name,
      };
}

class InventoryUpdateAction {
  const InventoryUpdateAction({
    required this.receiptLineId,
    required this.catalogProductId,
    required this.productName,
    required this.type,
    required this.trace,
  });

  factory InventoryUpdateAction.fromJson(Map<String, Object?> json) =>
      InventoryUpdateAction(
        receiptLineId: json['receiptLineId']! as String,
        catalogProductId: json['catalogProductId'] as String?,
        productName: json['productName']! as String,
        type: InventoryUpdateActionType.values.byName(json['type']! as String),
        trace: InventoryUpdateTrace.fromJson(
          json['trace']! as Map<String, Object?>,
        ),
      );

  final String receiptLineId;
  final String? catalogProductId;
  final String productName;
  final InventoryUpdateActionType type;
  final InventoryUpdateTrace trace;

  Map<String, Object?> toJson() => {
        'receiptLineId': receiptLineId,
        'catalogProductId': catalogProductId,
        'productName': productName,
        'type': type.name,
        'trace': trace.toJson(),
      };
}

class InventoryUpdatePlan {
  InventoryUpdatePlan({
    required this.receiptId,
    required Iterable<InventoryUpdateAction> actions,
  }) : actions = List.unmodifiable(actions);

  factory InventoryUpdatePlan.fromJson(Map<String, Object?> json) =>
      InventoryUpdatePlan(
        receiptId: json['receiptId']! as String,
        actions: (json['actions']! as List<Object?>).map(
          (value) => InventoryUpdateAction.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );

  final String receiptId;
  final List<InventoryUpdateAction> actions;

  List<InventoryUpdateAction> actionsOf(InventoryUpdateActionType type) =>
      List.unmodifiable(actions.where((action) => action.type == type));

  int get productsAdded =>
      actionsOf(InventoryUpdateActionType.addNewProduct).length;
  int get productsUpdated =>
      actionsOf(InventoryUpdateActionType.increaseQuantity).length;
  int get productsIgnored =>
      actionsOf(InventoryUpdateActionType.ignoreDuplicate).length;
  int get unknownProducts =>
      actionsOf(InventoryUpdateActionType.unknownProduct).length;

  Map<String, Object> toJson() => {
        'receiptId': receiptId,
        'actions': [for (final action in actions) action.toJson()],
      };
}

class InventoryUpdateResult {
  InventoryUpdateResult({
    required this.plan,
    required Iterable<String> productsAdded,
    required Iterable<String> productsUpdated,
    required Iterable<String> productsIgnored,
    required Iterable<String> unknownProducts,
  })  : productsAdded = List.unmodifiable(productsAdded),
        productsUpdated = List.unmodifiable(productsUpdated),
        productsIgnored = List.unmodifiable(productsIgnored),
        unknownProducts = List.unmodifiable(unknownProducts);

  factory InventoryUpdateResult.fromJson(Map<String, Object?> json) =>
      InventoryUpdateResult(
        plan: InventoryUpdatePlan.fromJson(
          json['plan']! as Map<String, Object?>,
        ),
        productsAdded: (json['productsAdded']! as List<Object?>).cast<String>(),
        productsUpdated:
            (json['productsUpdated']! as List<Object?>).cast<String>(),
        productsIgnored:
            (json['productsIgnored']! as List<Object?>).cast<String>(),
        unknownProducts:
            (json['unknownProducts']! as List<Object?>).cast<String>(),
      );

  final InventoryUpdatePlan plan;
  final List<String> productsAdded;
  final List<String> productsUpdated;
  final List<String> productsIgnored;
  final List<String> unknownProducts;

  Map<String, Object> toJson() => {
        'plan': plan.toJson(),
        'productsAdded': productsAdded,
        'productsUpdated': productsUpdated,
        'productsIgnored': productsIgnored,
        'unknownProducts': unknownProducts,
      };
}
