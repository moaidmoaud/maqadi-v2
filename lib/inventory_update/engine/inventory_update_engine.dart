import '../../product_matching_v2/domain/product_decision.dart';
import '../../product_matching_v2/domain/product_match_result.dart';
import '../../utils/arabic_text.dart';
import '../domain/inventory_update_models.dart';

class InventoryUpdateEngine {
  const InventoryUpdateEngine();

  InventoryUpdatePlan createPlan({
    required InventoryUpdateInput input,
    required Iterable<InventoryProductSnapshot> inventory,
    Set<String> processedSourceKeys = const {},
  }) {
    if (input.receiptId.trim().isEmpty) {
      throw ArgumentError.value(
        input.receiptId,
        'input.receiptId',
        'Receipt ID is required.',
      );
    }

    final projected = <String, _ProjectedProduct>{
      for (final item in inventory)
        _productKey(item.displayName): _ProjectedProduct(
          productId: item.productId,
          displayName: item.displayName,
          quantity: item.quantity,
        ),
    };
    final seenSourceKeys = <String>{...processedSourceKeys};
    final actions = <InventoryUpdateAction>[];

    for (final receiptProduct in input.products) {
      final match = receiptProduct.matchResult;
      final sourceKey = inventoryUpdateSourceKey(
        input.receiptId,
        match.receiptLineId,
      );
      final candidate = match.matchedProduct;
      final productName = candidate?.displayName.trim().isNotEmpty == true
          ? candidate!.displayName.trim()
          : 'Unknown product';
      final existing = candidate == null
          ? null
          : projected[_productKey(candidate.displayName)];

      if (!seenSourceKeys.add(sourceKey)) {
        actions.add(_action(
          match: match,
          productName: productName,
          type: InventoryUpdateActionType.ignoreDuplicate,
          reason: InventoryUpdateReason.duplicateReceiptLine,
          receiptQuantity: receiptProduct.quantity,
          existing: existing,
          newQuantity: existing?.quantity,
        ));
        continue;
      }

      if (!receiptProduct.quantity.isFinite || receiptProduct.quantity <= 0) {
        actions.add(_action(
          match: match,
          productName: productName,
          type: InventoryUpdateActionType.unknownProduct,
          reason: InventoryUpdateReason.invalidReceiptQuantity,
          receiptQuantity: receiptProduct.quantity,
          existing: existing,
          newQuantity: null,
        ));
        continue;
      }

      if (!_isFinalMatch(match) ||
          candidate == null ||
          candidate.productId.trim().isEmpty ||
          candidate.displayName.trim().isEmpty) {
        actions.add(_action(
          match: match,
          productName: productName,
          type: InventoryUpdateActionType.unknownProduct,
          reason: InventoryUpdateReason.productNotMatched,
          receiptQuantity: receiptProduct.quantity,
          existing: existing,
          newQuantity: null,
        ));
        continue;
      }

      if (existing == null) {
        final added = _ProjectedProduct(
          productId: null,
          displayName: candidate.displayName,
          quantity: receiptProduct.quantity,
        );
        projected[_productKey(candidate.displayName)] = added;
        actions.add(_action(
          match: match,
          productName: candidate.displayName,
          type: InventoryUpdateActionType.addNewProduct,
          reason: InventoryUpdateReason.matchedProductNotInInventory,
          receiptQuantity: receiptProduct.quantity,
          existing: null,
          newQuantity: added.quantity,
        ));
        continue;
      }

      final previous = existing.snapshot;
      existing.quantity += receiptProduct.quantity;
      actions.add(InventoryUpdateAction(
        receiptLineId: match.receiptLineId,
        catalogProductId: candidate.productId,
        productName: candidate.displayName,
        type: InventoryUpdateActionType.increaseQuantity,
        trace: InventoryUpdateTrace(
          previousInventory: previous,
          receiptQuantity: receiptProduct.quantity,
          newQuantity: existing.quantity,
          reason: InventoryUpdateReason.matchedExistingProduct,
        ),
      ));
    }

    return InventoryUpdatePlan(receiptId: input.receiptId, actions: actions);
  }

  InventoryUpdateAction _action({
    required ProductMatchResult match,
    required String productName,
    required InventoryUpdateActionType type,
    required InventoryUpdateReason reason,
    required double receiptQuantity,
    required _ProjectedProduct? existing,
    required double? newQuantity,
  }) =>
      InventoryUpdateAction(
        receiptLineId: match.receiptLineId,
        catalogProductId: match.matchedProduct?.productId,
        productName: productName,
        type: type,
        trace: InventoryUpdateTrace(
          previousInventory: existing?.snapshot,
          receiptQuantity: receiptQuantity,
          newQuantity: newQuantity,
          reason: reason,
        ),
      );

  bool _isFinalMatch(ProductMatchResult match) =>
      match.decisionStatus == ProductDecisionStatus.matched &&
      match.status == ProductMatchStatus.matched;

  String _productKey(String name) => normalizeArabic(name);
}

class _ProjectedProduct {
  _ProjectedProduct({
    required this.productId,
    required this.displayName,
    required this.quantity,
  });

  final String? productId;
  final String displayName;
  double quantity;

  InventoryProductSnapshot get snapshot => InventoryProductSnapshot(
        productId: productId,
        displayName: displayName,
        quantity: quantity,
      );
}

String inventoryUpdateSourceKey(String receiptId, String receiptLineId) =>
    'inventory-update|${Uri.encodeComponent(receiptId)}|'
    '${Uri.encodeComponent(receiptLineId)}';
