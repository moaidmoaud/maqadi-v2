import '../models/price_history_models.dart';
import '../models/purchase_models.dart';
import '../repositories/price_history_repository.dart';

typedef PriceHistoryClock = DateTime Function();

class PriceHistoryService {
  PriceHistoryService({
    required PriceHistoryRepository repository,
    PriceHistoryClock? clock,
    this.defaultCurrency = 'SAR',
  })  : _repository = repository,
        _clock = clock ?? DateTime.now;

  final PriceHistoryRepository _repository;
  final PriceHistoryClock _clock;
  final String defaultCurrency;
  int _idCounter = 0;

  Future<List<PriceHistoryRecord>> recordPurchase(
    Purchase purchase,
    Iterable<PurchaseItem> items,
  ) async {
    final records =
        items.map((item) => _recordFor(purchase, item)).toList(growable: false);
    if (records.isEmpty) return const [];
    await _repository.applyChanges(added: records);
    return List.unmodifiable(records);
  }

  Future<void> reconcilePurchase({
    required Purchase previousPurchase,
    required List<PurchaseItem> previousItems,
    required Purchase updatedPurchase,
    required List<PurchaseItem> updatedItems,
  }) async {
    final existingRecords = {
      for (final record
          in await _repository.readByPurchase(previousPurchase.id))
        record.purchaseItemId: record,
    };
    final previousById = {
      for (final item in previousItems) item.id: item,
    };
    final updatedIds = updatedItems.map((item) => item.id).toSet();
    final removedIds = <String>{
      for (final item in previousItems)
        if (!updatedIds.contains(item.id)) item.id,
    };
    final added = <PriceHistoryRecord>[];

    for (final item in updatedItems) {
      final previousItem = previousById[item.id];
      final existingRecord = existingRecords[item.id];
      if (previousItem == null || existingRecord == null) {
        added.add(_recordFor(updatedPurchase, item));
        continue;
      }
      if (_snapshotChanged(
        previousPurchase,
        previousItem,
        updatedPurchase,
        item,
      )) {
        removedIds.add(item.id);
        added.add(_recordFor(updatedPurchase, item));
      }
    }

    if (removedIds.isEmpty && added.isEmpty) return;
    await _repository.applyChanges(
      added: added,
      removedPurchaseItemIds: removedIds,
    );
  }

  Future<void> removePurchaseHistory(String purchaseId) async {
    final records = await _repository.readByPurchase(purchaseId);
    if (records.isEmpty) return;
    await _repository.applyChanges(
      removedPurchaseItemIds:
          records.map((record) => record.purchaseItemId).toSet(),
    );
  }

  Future<List<PriceHistoryRecord>> historyForProduct(String productId) async {
    if (productId.trim().isEmpty) {
      throw ArgumentError.value(
        productId,
        'productId',
        'Product ID is required.',
      );
    }
    final records = (await _repository.readByProduct(productId)).toList();
    records.sort((a, b) {
      final byPurchaseDate = b.purchaseDate.compareTo(a.purchaseDate);
      if (byPurchaseDate != 0) return byPurchaseDate;
      final byCreatedAt = b.createdAt.compareTo(a.createdAt);
      return byCreatedAt != 0 ? byCreatedAt : b.id.compareTo(a.id);
    });
    return List.unmodifiable(records);
  }

  Future<List<PriceHistoryRecord>> snapshotForPurchase(String purchaseId) =>
      _repository.readByPurchase(purchaseId);

  Future<void> restorePurchaseSnapshot(
    String purchaseId,
    List<PriceHistoryRecord> records,
  ) =>
      _repository.replacePurchaseRecords(purchaseId, records);

  PriceHistoryRecord _recordFor(
    Purchase purchase,
    PurchaseItem item,
  ) {
    if (purchase.id.trim().isEmpty ||
        purchase.storeId.trim().isEmpty ||
        item.id.trim().isEmpty ||
        item.productId.trim().isEmpty ||
        item.purchaseId != purchase.id ||
        !item.finalUnitPrice.isFinite ||
        item.finalUnitPrice < 0 ||
        defaultCurrency.trim().isEmpty) {
      throw ArgumentError('Cannot record an invalid purchase price.');
    }
    final createdAt = _clock();
    _idCounter++;
    return PriceHistoryRecord(
      id: 'price_${createdAt.microsecondsSinceEpoch}_$_idCounter',
      productId: item.productId,
      purchaseId: purchase.id,
      purchaseItemId: item.id,
      storeId: purchase.storeId,
      purchaseDate: purchase.purchaseDate,
      unitPrice: item.finalUnitPrice,
      currency: defaultCurrency,
      createdAt: createdAt,
    );
  }

  bool _snapshotChanged(
    Purchase previousPurchase,
    PurchaseItem previousItem,
    Purchase updatedPurchase,
    PurchaseItem updatedItem,
  ) =>
      previousItem.productId != updatedItem.productId ||
      previousItem.finalUnitPrice != updatedItem.finalUnitPrice ||
      previousPurchase.storeId != updatedPurchase.storeId ||
      previousPurchase.purchaseDate != updatedPurchase.purchaseDate;
}
