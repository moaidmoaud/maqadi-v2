import '../models/inventory_models.dart';
import '../models/purchase_models.dart';
import '../repositories/purchase_repository.dart';
import 'inventory_service.dart';

typedef PurchaseClock = DateTime Function();
typedef InventoryChangePersister = Future<void> Function();

class PurchaseService {
  PurchaseService({
    required PurchaseRepository repository,
    required InventoryService inventoryService,
    PurchaseClock? clock,
    InventoryChangePersister? persistInventory,
  })  : _repository = repository,
        _inventory = inventoryService,
        _clock = clock ?? DateTime.now,
        _persistInventory = persistInventory;

  final PurchaseRepository _repository;
  final InventoryService _inventory;
  final PurchaseClock _clock;
  final InventoryChangePersister? _persistInventory;

  double calculateSubtotal(Iterable<PurchaseItem> items) => _money(
        items.fold<double>(
          0,
          (total, item) => total + item.quantity * item.unitPrice,
        ),
      );

  double calculateDiscount(Iterable<PurchaseItem> items) {
    final subtotal = calculateSubtotal(items);
    final discountedTotal = _money(
      items.fold<double>(
        0,
        (total, item) => total + item.quantity * item.finalUnitPrice,
      ),
    );
    return _money(subtotal - discountedTotal);
  }

  double calculateTax(Iterable<PurchaseItem> items, {required double taxRate}) {
    _validateTaxRate(taxRate);
    final taxableAmount = calculateSubtotal(items) - calculateDiscount(items);
    return _money(taxableAmount * taxRate);
  }

  double calculatePurchaseTotal(
    Iterable<PurchaseItem> items, {
    required double taxRate,
  }) {
    final subtotal = calculateSubtotal(items);
    final discount = calculateDiscount(items);
    final tax = calculateTax(items, taxRate: taxRate);
    return _money(subtotal - discount + tax);
  }

  Future<Purchase> createPurchase({
    required String id,
    required String storeId,
    required DateTime purchaseDate,
    required List<PurchaseItem> items,
    double taxRate = 0,
    String? notes,
  }) async {
    final now = _clock();
    final normalizedItems = _normalizeItems(id, items);
    final purchase = _buildPurchase(
      id: id,
      storeId: storeId,
      purchaseDate: purchaseDate,
      items: normalizedItems,
      taxRate: taxRate,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    validatePurchase(purchase, normalizedItems);
    _validateInventoryTargets(normalizedItems);

    final addedBatches = <_AddedPurchaseBatch>[];
    final persistedItems = <PurchaseItem>[];
    var repositoryCreated = false;
    try {
      for (final item in normalizedItems) {
        final pantryItem = _inventory.findById(item.productId)!;
        final batch = _inventory.addBatch(
          pantryItem,
          quantity: item.quantity,
          receivedAt: purchase.purchaseDate,
          expiresAt: item.expiryDate,
          batchId: item.batchId,
          note: 'شراء ${purchase.id}',
          movementType: 'شراء',
        );
        addedBatches.add(_AddedPurchaseBatch(pantryItem, batch));
        persistedItems.add(item.copyWith(batchId: batch.id));
      }
      await _repository.createPurchase(purchase, persistedItems);
      repositoryCreated = true;
      await _persistInventory?.call();
      return purchase;
    } catch (_) {
      if (repositoryCreated) await _repository.deletePurchase(purchase.id);
      for (final added in addedBatches.reversed) {
        if (added.item.batches.contains(added.batch)) {
          _inventory.deleteBatch(added.item, added.batch);
        }
      }
      rethrow;
    }
  }

  Future<Purchase> updatePurchase({
    required Purchase purchase,
    required List<PurchaseItem> items,
    required double taxRate,
  }) async {
    final existing = await _repository.readPurchase(purchase.id);
    if (existing == null) {
      throw StateError('Purchase ${purchase.id} does not exist.');
    }
    final existingItems = await _repository.readPurchaseDetails(purchase.id);
    final normalizedItems = _normalizeItems(purchase.id, items);
    final updated = _buildPurchase(
      id: purchase.id,
      storeId: purchase.storeId,
      purchaseDate: purchase.purchaseDate,
      items: normalizedItems,
      taxRate: taxRate,
      notes: purchase.notes,
      createdAt: existing.createdAt,
      updatedAt: _clock(),
    );
    validatePurchase(updated, normalizedItems);
    _validateInventoryTargets(normalizedItems, replacing: existingItems);

    final persistedItems = _reconcileInventory(
      existingItems,
      updated,
      normalizedItems,
    );
    await _repository.updatePurchase(updated, persistedItems);
    await _persistInventory?.call();
    return updated;
  }

  Future<void> deletePurchase(String purchaseId) async {
    final purchase = await _repository.readPurchase(purchaseId);
    if (purchase == null) return;
    final items = await _repository.readPurchaseDetails(purchaseId);
    for (final item in items) {
      final pantryItem = _inventory.findById(item.productId);
      final batchId = item.batchId;
      if (pantryItem == null || batchId == null) continue;
      final batch = _inventory.findBatchById(pantryItem, batchId);
      if (batch != null) _inventory.deleteBatch(pantryItem, batch);
    }
    await _repository.deletePurchase(purchaseId);
    await _persistInventory?.call();
  }

  void validatePurchase(Purchase purchase, List<PurchaseItem> items) {
    if (purchase.id.trim().isEmpty) {
      throw ArgumentError.value(purchase.id, 'id', 'Purchase ID is required.');
    }
    if (purchase.storeId.trim().isEmpty) {
      throw ArgumentError.value(
        purchase.storeId,
        'storeId',
        'Store ID is required.',
      );
    }
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'A purchase needs an item.');
    }
    final itemIds = <String>{};
    for (final item in items) {
      if (item.id.trim().isEmpty || !itemIds.add(item.id)) {
        throw ArgumentError.value(
          item.id,
          'item.id',
          'Purchase item IDs must be unique and non-empty.',
        );
      }
      if (item.purchaseId != purchase.id) {
        throw ArgumentError.value(
          item.purchaseId,
          'item.purchaseId',
          'Purchase item belongs to a different purchase.',
        );
      }
      if (item.productId.trim().isEmpty) {
        throw ArgumentError.value(
          item.productId,
          'item.productId',
          'Product ID is required.',
        );
      }
      if (!item.quantity.isFinite || item.quantity <= 0) {
        throw ArgumentError.value(
          item.quantity,
          'item.quantity',
          'Quantity must be greater than zero.',
        );
      }
      if (!item.unitPrice.isFinite || item.unitPrice < 0) {
        throw ArgumentError.value(
          item.unitPrice,
          'item.unitPrice',
          'Unit price cannot be negative.',
        );
      }
      if (!item.finalUnitPrice.isFinite ||
          item.finalUnitPrice < 0 ||
          item.finalUnitPrice > item.unitPrice) {
        throw ArgumentError.value(
          item.finalUnitPrice,
          'item.finalUnitPrice',
          'Final unit price must be between zero and the unit price.',
        );
      }
    }
    if (purchase.subtotal < 0 ||
        purchase.discount < 0 ||
        purchase.tax < 0 ||
        purchase.total < 0) {
      throw ArgumentError('Purchase totals cannot be negative.');
    }
  }

  Future<Purchase?> readPurchase(String purchaseId) =>
      _repository.readPurchase(purchaseId);

  Future<List<Purchase>> readPurchaseHistory() =>
      _repository.readPurchaseHistory();

  Future<List<Purchase>> readPurchasesByDate(DateTime date) =>
      _repository.readPurchasesByDate(date);

  Future<List<Purchase>> readPurchasesByStore(String storeId) =>
      _repository.readPurchasesByStore(storeId);

  Future<List<PurchaseItem>> readPurchaseDetails(String purchaseId) =>
      _repository.readPurchaseDetails(purchaseId);

  Purchase _buildPurchase({
    required String id,
    required String storeId,
    required DateTime purchaseDate,
    required List<PurchaseItem> items,
    required double taxRate,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? notes,
  }) {
    _validateTaxRate(taxRate);
    final subtotal = calculateSubtotal(items);
    final discount = calculateDiscount(items);
    final tax = calculateTax(items, taxRate: taxRate);
    return Purchase(
      id: id.trim(),
      storeId: storeId.trim(),
      purchaseDate: purchaseDate,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: _money(subtotal - discount + tax),
      notes: _clean(notes),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  List<PurchaseItem> _normalizeItems(
    String purchaseId,
    Iterable<PurchaseItem> items,
  ) =>
      items
          .map(
            (item) => item.copyWith(
              purchaseId: purchaseId.trim(),
              lineTotal: _money(item.quantity * item.finalUnitPrice),
              batchId: _clean(item.batchId),
              clearBatchId: _clean(item.batchId) == null,
            ),
          )
          .toList();

  void _validateInventoryTargets(
    Iterable<PurchaseItem> items, {
    Iterable<PurchaseItem> replacing = const [],
  }) {
    final replaceableBatches = replacing
        .where((item) => item.batchId != null)
        .map((item) => '${item.productId}|${item.batchId}')
        .toSet();
    final requestedBatches = <String>{};
    for (final item in items) {
      final pantryItem = _inventory.findById(item.productId);
      if (pantryItem == null) {
        throw ArgumentError.value(
          item.productId,
          'item.productId',
          'Product does not exist in inventory.',
        );
      }
      final batchId = item.batchId;
      if (batchId == null) continue;
      final key = '${item.productId}|$batchId';
      if (!requestedBatches.add(key)) {
        throw ArgumentError.value(
          batchId,
          'item.batchId',
          'Batch IDs must be unique for a product.',
        );
      }
      if (_inventory.findBatchById(pantryItem, batchId) != null &&
          !replaceableBatches.contains(key)) {
        throw ArgumentError.value(
          batchId,
          'item.batchId',
          'Batch ID already exists for this product.',
        );
      }
    }
  }

  List<PurchaseItem> _reconcileInventory(
    List<PurchaseItem> existingItems,
    Purchase updated,
    List<PurchaseItem> updatedItems,
  ) {
    final previousById = {for (final item in existingItems) item.id: item};
    final updatedIds = updatedItems.map((item) => item.id).toSet();

    for (final oldItem in existingItems) {
      if (updatedIds.contains(oldItem.id)) continue;
      _deleteRemainingBatch(oldItem);
    }

    final result = <PurchaseItem>[];
    for (final item in updatedItems) {
      final oldItem = previousById[item.id];
      if (oldItem == null || oldItem.productId != item.productId) {
        if (oldItem != null) _deleteRemainingBatch(oldItem);
        result.add(_addPurchasedBatch(updated, item, item.quantity));
        continue;
      }

      final pantryItem = _inventory.findById(item.productId)!;
      final oldBatchId = oldItem.batchId;
      final oldBatch = oldBatchId == null
          ? null
          : _inventory.findBatchById(pantryItem, oldBatchId);
      if (oldBatch == null) {
        final addedQuantity = item.quantity - oldItem.quantity;
        result.add(
          addedQuantity > 0
              ? _addPurchasedBatch(updated, item, addedQuantity)
              : item.copyWith(clearBatchId: true),
        );
        continue;
      }

      final consumed = (oldItem.quantity - oldBatch.quantity)
          .clamp(0, oldItem.quantity)
          .toDouble();
      final remaining = item.quantity - consumed;
      if (remaining <= 0) {
        _inventory.deleteBatch(pantryItem, oldBatch);
        result.add(item.copyWith(clearBatchId: true));
      } else {
        _inventory.updateBatch(
          pantryItem,
          oldBatch,
          quantity: remaining,
          receivedAt: updated.purchaseDate,
          expiresAt: item.expiryDate,
          batchId: item.batchId ?? oldBatch.id,
          note: 'شراء ${updated.id}',
        );
        result.add(item.copyWith(batchId: oldBatch.id));
      }
    }
    return result;
  }

  PurchaseItem _addPurchasedBatch(
    Purchase purchase,
    PurchaseItem item,
    double quantity,
  ) {
    final pantryItem = _inventory.findById(item.productId)!;
    final batch = _inventory.addBatch(
      pantryItem,
      quantity: quantity,
      receivedAt: purchase.purchaseDate,
      expiresAt: item.expiryDate,
      batchId: item.batchId,
      note: 'شراء ${purchase.id}',
      movementType: 'شراء',
    );
    return item.copyWith(batchId: batch.id);
  }

  void _deleteRemainingBatch(PurchaseItem item) {
    final pantryItem = _inventory.findById(item.productId);
    final batchId = item.batchId;
    if (pantryItem == null || batchId == null) return;
    final batch = _inventory.findBatchById(pantryItem, batchId);
    if (batch != null) _inventory.deleteBatch(pantryItem, batch);
  }

  void _validateTaxRate(double taxRate) {
    if (!taxRate.isFinite || taxRate < 0 || taxRate > 1) {
      throw ArgumentError.value(
        taxRate,
        'taxRate',
        'Tax rate must be between zero and one.',
      );
    }
  }

  double _money(double value) => (value * 100).round() / 100;

  String? _clean(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }
}

class _AddedPurchaseBatch {
  const _AddedPurchaseBatch(this.item, this.batch);

  final PantryItem item;
  final InventoryBatch batch;
}
