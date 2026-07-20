import '../models/price_history_models.dart';

abstract interface class PriceHistoryRepository {
  Future<void> applyChanges({
    List<PriceHistoryRecord> added = const [],
    Set<String> removedPurchaseItemIds = const {},
  });

  Future<void> replacePurchaseRecords(
    String purchaseId,
    List<PriceHistoryRecord> records,
  );

  Future<List<PriceHistoryRecord>> readByProduct(String productId);

  Future<List<PriceHistoryRecord>> readByPurchase(String purchaseId);
}
