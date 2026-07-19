import '../models/purchase_models.dart';

abstract interface class PurchaseRepository {
  Future<Purchase> createPurchase(Purchase purchase, List<PurchaseItem> items);

  Future<Purchase> updatePurchase(Purchase purchase, List<PurchaseItem> items);

  Future<void> deletePurchase(String purchaseId);

  Future<Purchase?> readPurchase(String purchaseId);

  Future<List<Purchase>> readPurchaseHistory();

  Future<List<Purchase>> readPurchasesByDate(DateTime date);

  Future<List<Purchase>> readPurchasesByStore(String storeId);

  Future<List<PurchaseItem>> readPurchaseDetails(String purchaseId);
}
