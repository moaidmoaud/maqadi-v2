import 'dart:async';
import 'dart:collection';

import '../models/inventory_models.dart';
import '../models/price_history_models.dart';
import '../models/purchase_models.dart';
import '../purchase/application/purchase_creation_gateway.dart';
import '../purchase/domain/purchase_creation_command.dart';
import '../repositories/purchase_repository.dart';
import '../utils/arabic_text.dart';
import 'inventory_service.dart';
import 'price_history_service.dart';
import 'store_service.dart';

typedef PurchaseClock = DateTime Function();
typedef InventoryChangePersister = Future<void> Function();

class PurchaseService implements PurchaseCreationGateway {
  PurchaseService({
    required PurchaseRepository repository,
    required InventoryService inventoryService,
    PriceHistoryService? priceHistoryService,
    StoreService? storeService,
    PurchaseClock? clock,
    InventoryChangePersister? persistInventory,
  })  : _repository = repository,
        _inventory = inventoryService,
        _priceHistory = priceHistoryService,
        _storeService = storeService,
        _clock = clock ?? DateTime.now,
        _persistInventory = persistInventory;

  final PurchaseRepository _repository;
  final InventoryService _inventory;
  final PriceHistoryService? _priceHistory;
  final StoreService? _storeService;
  final PurchaseClock _clock;
  final InventoryChangePersister? _persistInventory;
  int _idCounter = 0;
  final Queue<_QueuedPurchaseWrite> _writeQueue = Queue();
  bool _writeActive = false;
  final Map<String, Future<PurchaseCreationResult>> _creationRequests = {};

  List<PurchaseProductOption> availableProducts() => _inventory.items
      .map(
        (item) => PurchaseProductOption(
          id: item.id,
          name: item.name,
          category: item.category,
          unit: item.unit,
        ),
      )
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  String productNameFor(String productId) =>
      _inventory.findById(productId)?.name ?? productId;

  String newPurchaseId() => _newId('purchase');

  @override
  List<PurchaseProductOption> purchaseCreationProducts() => availableProducts();

  @override
  Future<List<Store>> purchaseCreationStores() => availableStoresForPurchase();

  @override
  Future<PurchaseCreationResult> createFromCommand(
    PurchaseCreationCommand command,
  ) {
    final requestId = command.requestId.trim();
    if (requestId.isEmpty) {
      return Future.error(
        const PurchaseCreationException(
          PurchaseCreationErrorCode.validation,
          'معرّف طلب الشراء مطلوب.',
        ),
      );
    }
    final existing = _creationRequests[requestId];
    if (existing != null) return existing;
    final operation = _createFromCommand(command);
    _creationRequests[requestId] = operation;
    operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        if (identical(_creationRequests[requestId], operation)) {
          _creationRequests.remove(requestId);
        }
      },
    );
    return operation;
  }

  Future<PurchaseCreationResult> _createFromCommand(
    PurchaseCreationCommand command,
  ) async {
    try {
      final purchaseId = newPurchaseId();
      final purchase = await createPurchase(
        id: purchaseId,
        storeId: command.storeId,
        purchaseDate: command.purchaseDate,
        items: [
          for (final item in command.items)
            PurchaseItem(
              id: _newId('purchase-item'),
              purchaseId: purchaseId,
              productId: item.productId,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              finalUnitPrice: item.unitPrice,
              lineTotal: item.quantity * item.unitPrice,
              expiryDate: item.expiryDate,
              batchId: item.batchId,
            ),
        ],
        discountAmount: command.discount,
        taxAmount: command.tax,
        notes: command.notes,
      );
      return PurchaseCreationResult(
        purchaseId: purchase.id,
        total: purchase.total,
        purchaseDate: purchase.purchaseDate,
      );
    } on PurchaseValidationException catch (error) {
      throw PurchaseCreationException(
        PurchaseCreationErrorCode.validation,
        error.message,
        cause: error,
      );
    } on StoreValidationException catch (error) {
      throw PurchaseCreationException(
        PurchaseCreationErrorCode.validation,
        error.message,
        cause: error,
      );
    } on ArgumentError catch (error) {
      throw PurchaseCreationException(
        PurchaseCreationErrorCode.validation,
        'بيانات الإيصال غير صالحة لإنشاء عملية شراء.',
        cause: error,
      );
    } catch (error) {
      throw PurchaseCreationException(
        PurchaseCreationErrorCode.creation,
        'تعذر حفظ عملية الشراء من الإيصال.',
        cause: error,
      );
    }
  }

  PurchaseItem createDraftItem(String productId, {String purchaseId = ''}) {
    if (_inventory.findById(productId) == null) {
      throw ArgumentError.value(
        productId,
        'productId',
        'Product does not exist in inventory.',
      );
    }
    return PurchaseItem(
      id: _newId('purchase-item'),
      purchaseId: purchaseId,
      productId: productId,
      quantity: 1,
      unitPrice: 0,
      finalUnitPrice: 0,
      lineTotal: 0,
    );
  }

  PurchaseTotals previewTotals(
    Iterable<PurchaseItem> items, {
    required double discount,
    required double tax,
  }) {
    final itemList = items.toList();
    _validateAmountInput(itemList, discount: discount, tax: tax);
    final subtotal = calculateSubtotal(itemList);
    return PurchaseTotals(
      subtotal: subtotal,
      discount: _money(discount),
      tax: _money(tax),
      total: _money(subtotal - discount + tax),
    );
  }

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
    double? discountAmount,
    double? taxAmount,
    String? notes,
  }) =>
      _serializeWrite(
        () => _createPurchase(
          id: id,
          storeId: storeId,
          purchaseDate: purchaseDate,
          items: items,
          taxRate: taxRate,
          discountAmount: discountAmount,
          taxAmount: taxAmount,
          notes: notes,
        ),
      );

  Future<Purchase> _createPurchase({
    required String id,
    required String storeId,
    required DateTime purchaseDate,
    required List<PurchaseItem> items,
    double taxRate = 0,
    double? discountAmount,
    double? taxAmount,
    String? notes,
  }) async {
    final resolvedStoreId =
        (await _storeService?.storeForNewPurchase(storeId))?.id ?? storeId;
    final now = _clock();
    final usesAmounts = discountAmount != null || taxAmount != null;
    final normalizedItems = usesAmounts
        ? _itemsWithDiscount(
            id,
            items,
            discount: discountAmount ?? 0,
            tax: taxAmount ?? 0,
          )
        : _normalizeItems(id, items);
    final purchase = usesAmounts
        ? _buildPurchaseWithAmounts(
            id: id,
            storeId: resolvedStoreId,
            purchaseDate: purchaseDate,
            items: normalizedItems,
            discount: discountAmount ?? 0,
            tax: taxAmount ?? 0,
            notes: notes,
            createdAt: now,
            updatedAt: now,
          )
        : _buildPurchase(
            id: id,
            storeId: resolvedStoreId,
            purchaseDate: purchaseDate,
            items: normalizedItems,
            taxRate: taxRate,
            notes: notes,
            createdAt: now,
            updatedAt: now,
          );
    validatePurchase(purchase, normalizedItems);
    _validateInventoryTargets(normalizedItems);

    final inventorySnapshot = _InventorySnapshot.capture(_inventory);
    final purchaseSnapshot = await _purchaseSnapshot(purchase.id);
    final historySnapshot = await _priceHistory?.snapshotForPurchase(
      purchase.id,
    );
    final persistedItems = <PurchaseItem>[];
    var inventoryTouched = false;
    var purchaseTouched = false;
    var historyTouched = false;
    try {
      for (final item in normalizedItems) {
        inventoryTouched = true;
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
        persistedItems.add(item.copyWith(batchId: batch.id));
      }
      purchaseTouched = true;
      await _repository.createPurchase(purchase, persistedItems);
      historyTouched = _priceHistory != null;
      await _priceHistory?.recordPurchase(purchase, persistedItems);
      await _persistInventory?.call();
      return purchase;
    } catch (error, stackTrace) {
      await _rollbackUnitOfWork(
        purchaseId: purchase.id,
        purchaseSnapshot: purchaseSnapshot,
        historySnapshot: historySnapshot,
        inventorySnapshot: inventorySnapshot,
        restorePurchase: purchaseTouched,
        restoreHistory: historyTouched,
        restoreInventory: inventoryTouched,
        originalError: error,
        originalStackTrace: stackTrace,
      );
    }
  }

  Future<Purchase> updatePurchase({
    required Purchase purchase,
    required List<PurchaseItem> items,
    double taxRate = 0,
    double? discountAmount,
    double? taxAmount,
  }) =>
      _serializeWrite(
        () => _updatePurchase(
          purchase: purchase,
          items: items,
          taxRate: taxRate,
          discountAmount: discountAmount,
          taxAmount: taxAmount,
        ),
      );

  Future<Purchase> _updatePurchase({
    required Purchase purchase,
    required List<PurchaseItem> items,
    double taxRate = 0,
    double? discountAmount,
    double? taxAmount,
  }) async {
    final existing = await _repository.readPurchase(purchase.id);
    if (existing == null) {
      throw StateError('Purchase ${purchase.id} does not exist.');
    }
    final resolvedStoreId = (await _storeService?.storeForPurchaseEdit(
          purchase.storeId,
          previousStoreId: existing.storeId,
        ))
            ?.id ??
        purchase.storeId;
    final existingItems = await _repository.readPurchaseDetails(purchase.id);
    final usesAmounts = discountAmount != null || taxAmount != null;
    final normalizedItems = usesAmounts
        ? _itemsWithDiscount(
            purchase.id,
            items,
            discount: discountAmount ?? 0,
            tax: taxAmount ?? 0,
          )
        : _normalizeItems(purchase.id, items);
    final updated = usesAmounts
        ? _buildPurchaseWithAmounts(
            id: purchase.id,
            storeId: resolvedStoreId,
            purchaseDate: purchase.purchaseDate,
            items: normalizedItems,
            discount: discountAmount ?? 0,
            tax: taxAmount ?? 0,
            notes: purchase.notes,
            createdAt: existing.createdAt,
            updatedAt: _clock(),
          )
        : _buildPurchase(
            id: purchase.id,
            storeId: resolvedStoreId,
            purchaseDate: purchase.purchaseDate,
            items: normalizedItems,
            taxRate: taxRate,
            notes: purchase.notes,
            createdAt: existing.createdAt,
            updatedAt: _clock(),
          );
    validatePurchase(updated, normalizedItems);
    _validateInventoryTargets(normalizedItems, replacing: existingItems);

    final inventorySnapshot = _InventorySnapshot.capture(_inventory);
    final purchaseSnapshot = _PurchaseSnapshot(existing, existingItems);
    final historySnapshot = await _priceHistory?.snapshotForPurchase(
      purchase.id,
    );
    var historyTouched = false;
    var inventoryTouched = false;
    var purchaseTouched = false;
    try {
      historyTouched = _priceHistory != null;
      await _priceHistory?.reconcilePurchase(
        previousPurchase: existing,
        previousItems: existingItems,
        updatedPurchase: updated,
        updatedItems: normalizedItems,
      );
      inventoryTouched = true;
      final persistedItems = _reconcileInventory(
        existingItems,
        updated,
        normalizedItems,
      );
      purchaseTouched = true;
      await _repository.updatePurchase(updated, persistedItems);
      await _persistInventory?.call();
      return updated;
    } catch (error, stackTrace) {
      await _rollbackUnitOfWork(
        purchaseId: purchase.id,
        purchaseSnapshot: purchaseSnapshot,
        historySnapshot: historySnapshot,
        inventorySnapshot: inventorySnapshot,
        restorePurchase: purchaseTouched,
        restoreHistory: historyTouched,
        restoreInventory: inventoryTouched,
        originalError: error,
        originalStackTrace: stackTrace,
      );
    }
  }

  Future<void> deletePurchase(String purchaseId) =>
      _serializeWrite(() => _deletePurchase(purchaseId));

  Future<void> _deletePurchase(String purchaseId) async {
    final purchase = await _repository.readPurchase(purchaseId);
    if (purchase == null) return;
    final items = await _repository.readPurchaseDetails(purchaseId);
    final inventorySnapshot = _InventorySnapshot.capture(_inventory);
    final purchaseSnapshot = _PurchaseSnapshot(purchase, items);
    final historySnapshot = await _priceHistory?.snapshotForPurchase(
      purchaseId,
    );
    var historyTouched = false;
    var inventoryTouched = false;
    var purchaseTouched = false;
    try {
      historyTouched = _priceHistory != null;
      await _priceHistory?.removePurchaseHistory(purchaseId);
      inventoryTouched = true;
      for (final item in items) {
        final pantryItem = _inventory.findById(item.productId);
        final batchId = item.batchId;
        if (pantryItem == null || batchId == null) continue;
        final batch = _inventory.findBatchById(pantryItem, batchId);
        if (batch != null) _inventory.deleteBatch(pantryItem, batch);
      }
      purchaseTouched = true;
      await _repository.deletePurchase(purchaseId);
      await _persistInventory?.call();
    } catch (error, stackTrace) {
      await _rollbackUnitOfWork(
        purchaseId: purchaseId,
        purchaseSnapshot: purchaseSnapshot,
        historySnapshot: historySnapshot,
        inventorySnapshot: inventorySnapshot,
        restorePurchase: purchaseTouched,
        restoreHistory: historyTouched,
        restoreInventory: inventoryTouched,
        originalError: error,
        originalStackTrace: stackTrace,
      );
    }
  }

  Future<void> deletePurchaseSafely(String purchaseId) =>
      _serializeWrite(() => _deletePurchaseSafely(purchaseId));

  Future<void> _deletePurchaseSafely(String purchaseId) async {
    final purchase = await _repository.readPurchase(purchaseId);
    if (purchase == null) return;
    final items = await _repository.readPurchaseDetails(purchaseId);
    for (final item in items) {
      final pantryItem = _inventory.findById(item.productId);
      final batchId = item.batchId;
      if (pantryItem == null || batchId == null) {
        throw const PurchaseDeletionException(
          'لا يمكن حذف عملية الشراء لأن مخزونها لم يعد قابلًا للعكس بأمان.',
        );
      }
      final batch = _inventory.findBatchById(pantryItem, batchId);
      if (batch == null || (batch.quantity - item.quantity).abs() > 0.000001) {
        throw const PurchaseDeletionException(
          'لا يمكن حذف عملية الشراء بعد استهلاك أو تعديل إحدى دفعاتها.',
        );
      }
    }
    await _deletePurchase(purchaseId);
  }

  Future<List<String>> readStoreIds() async {
    if (_storeService case final storeService?) {
      return (await storeService.activeStores())
          .map((store) => store.id)
          .toList(growable: false);
    }
    final purchases = await _repository.readPurchaseHistory();
    final stores = purchases
        .map((purchase) => purchase.storeId.trim())
        .where((store) => store.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    return stores;
  }

  Future<List<Store>> availableStoresForPurchase({
    String? currentStoreId,
  }) async {
    if (_storeService case final storeService?) {
      final stores = (await storeService.activeStores()).toList();
      final currentId = currentStoreId?.trim();
      if (currentId != null &&
          currentId.isNotEmpty &&
          !stores.any((store) => store.id == currentId)) {
        final current = await storeService.readStore(currentId);
        if (current != null) stores.add(current);
      }
      stores.sort((a, b) => a.name.compareTo(b.name));
      return List.unmodifiable(stores);
    }
    final timestamp = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return (await readStoreIds())
        .map(
          (storeId) => Store(id: storeId, name: storeId, createdAt: timestamp),
        )
        .toList(growable: false);
  }

  Future<List<Store>> purchaseHistoryStores() async {
    if (_storeService case final storeService?) {
      return storeService.searchStores(filter: StoreStatusFilter.all);
    }
    return availableStoresForPurchase();
  }

  Future<List<PurchaseListEntry>> searchPurchases({
    String query = '',
    String? storeId,
    DateTime? date,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (startDate != null &&
        endDate != null &&
        _dateOnly(startDate).isAfter(_dateOnly(endDate))) {
      throw ArgumentError('Start date cannot be after end date.');
    }
    final normalizedQuery = normalizeArabic(query.trim());
    final normalizedStore = normalizeArabic(storeId?.trim() ?? '');
    final history = await _repository.readPurchaseHistory();
    final entries = <PurchaseListEntry>[];
    for (final purchase in history) {
      if (normalizedStore.isNotEmpty &&
          normalizeArabic(purchase.storeId) != normalizedStore) {
        continue;
      }
      final purchaseDay = _dateOnly(purchase.purchaseDate);
      if (date != null && purchaseDay != _dateOnly(date)) continue;
      if (date == null &&
          startDate != null &&
          purchaseDay.isBefore(_dateOnly(startDate))) {
        continue;
      }
      if (date == null &&
          endDate != null &&
          purchaseDay.isAfter(_dateOnly(endDate))) {
        continue;
      }
      final items = await _repository.readPurchaseDetails(purchase.id);
      final storeName = await _displayStoreName(purchase.storeId);
      if (normalizedQuery.isNotEmpty &&
          !_purchaseMatches(
            purchase,
            items,
            normalizedQuery,
            storeName: storeName,
          )) {
        continue;
      }
      entries.add(
        PurchaseListEntry(
          purchase: purchase,
          itemCount: items.length,
          storeName: storeName,
        ),
      );
    }
    entries.sort(
      (a, b) => b.purchase.purchaseDate.compareTo(a.purchase.purchaseDate),
    );
    return entries;
  }

  Future<PurchaseDetails?> readPurchaseWithDetails(String purchaseId) async {
    final purchase = await _repository.readPurchase(purchaseId);
    if (purchase == null) return null;
    return PurchaseDetails(
      purchase: purchase,
      storeName: await _displayStoreName(purchase.storeId),
      items: List.unmodifiable(
        await _repository.readPurchaseDetails(purchaseId),
      ),
    );
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

  bool _purchaseMatches(
    Purchase purchase,
    Iterable<PurchaseItem> items,
    String normalizedQuery, {
    String? storeName,
  }) {
    final values = <String>[
      purchase.id,
      purchase.storeId,
      storeName ?? '',
      purchase.notes ?? '',
      for (final item in items) ...[
        item.productId,
        productNameFor(item.productId),
        item.batchId ?? '',
      ],
    ];
    return values.any(
      (value) => normalizeArabic(value).contains(normalizedQuery),
    );
  }

  Future<String> _displayStoreName(String storeId) async =>
      await _storeService?.displayName(storeId) ?? storeId;

  Purchase _buildPurchaseWithAmounts({
    required String id,
    required String storeId,
    required DateTime purchaseDate,
    required List<PurchaseItem> items,
    required double discount,
    required double tax,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? notes,
  }) {
    if (storeId.trim().isEmpty) {
      throw const PurchaseValidationException('المتجر مطلوب.');
    }
    final totals = previewTotals(items, discount: discount, tax: tax);
    return Purchase(
      id: id.trim(),
      storeId: storeId.trim(),
      purchaseDate: purchaseDate,
      subtotal: totals.subtotal,
      discount: totals.discount,
      tax: totals.tax,
      total: totals.total,
      notes: _clean(notes),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

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

  List<PurchaseItem> _itemsWithDiscount(
    String purchaseId,
    Iterable<PurchaseItem> items, {
    required double discount,
    required double tax,
  }) {
    final source = items.toList();
    _validateAmountInput(source, discount: discount, tax: tax);
    final subtotal = calculateSubtotal(source);
    final discountedTotal = _money(subtotal - discount);
    var allocatedTotal = 0.0;
    final result = <PurchaseItem>[];
    for (var index = 0; index < source.length; index++) {
      final item = source[index];
      final gross = _money(item.quantity * item.unitPrice);
      final lineTotal = index == source.length - 1
          ? _money(discountedTotal - allocatedTotal)
          : _money(gross - (subtotal == 0 ? 0 : discount * (gross / subtotal)));
      allocatedTotal = _money(allocatedTotal + lineTotal);
      result.add(
        item.copyWith(
          purchaseId: purchaseId.trim(),
          finalUnitPrice:
              item.quantity == 0 ? item.unitPrice : lineTotal / item.quantity,
          lineTotal: lineTotal,
          batchId: _clean(item.batchId),
          clearBatchId: _clean(item.batchId) == null,
        ),
      );
    }
    return result;
  }

  void _validateAmountInput(
    List<PurchaseItem> items, {
    required double discount,
    required double tax,
  }) {
    if (items.isEmpty) {
      throw const PurchaseValidationException('يجب إضافة منتج واحد على الأقل.');
    }
    final ids = <String>{};
    for (final item in items) {
      if (item.id.trim().isEmpty || !ids.add(item.id)) {
        throw const PurchaseValidationException(
          'تعذر حفظ عناصر الشراء بسبب معرّف غير صالح.',
        );
      }
      if (item.productId.trim().isEmpty) {
        throw const PurchaseValidationException('المنتج مطلوب.');
      }
      if (!item.quantity.isFinite || item.quantity <= 0) {
        throw const PurchaseValidationException(
          'يجب أن تكون كمية كل منتج أكبر من صفر.',
        );
      }
      if (!item.unitPrice.isFinite || item.unitPrice < 0) {
        throw const PurchaseValidationException(
          'يجب ألا يكون سعر الوحدة سالبًا.',
        );
      }
    }
    final subtotal = calculateSubtotal(items);
    if (!discount.isFinite || discount < 0 || discount > subtotal) {
      throw const PurchaseValidationException(
        'يجب أن يكون الخصم بين صفر والإجمالي الفرعي.',
      );
    }
    if (!tax.isFinite || tax < 0) {
      throw const PurchaseValidationException('يجب ألا تكون الضريبة سالبة.');
    }
  }

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

  Future<T> _serializeWrite<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeQueue.add(_TypedQueuedPurchaseWrite(operation, completer));
    _startNextWrite();
    return completer.future;
  }

  void _startNextWrite() {
    if (_writeActive || _writeQueue.isEmpty) return;
    _writeActive = true;
    _writeQueue.removeFirst().run().whenComplete(() {
      _writeActive = false;
      _startNextWrite();
    });
  }

  Future<_PurchaseSnapshot> _purchaseSnapshot(String purchaseId) async {
    final purchase = await _repository.readPurchase(purchaseId);
    final items = purchase == null
        ? const <PurchaseItem>[]
        : await _repository.readPurchaseDetails(purchaseId);
    return _PurchaseSnapshot(purchase, items);
  }

  Future<void> _restorePurchaseSnapshot(
    String purchaseId,
    _PurchaseSnapshot snapshot,
  ) async {
    final current = await _repository.readPurchase(purchaseId);
    final purchase = snapshot.purchase;
    if (purchase == null) {
      if (current != null) await _repository.deletePurchase(purchaseId);
      return;
    }
    if (current == null) {
      await _repository.createPurchase(purchase, snapshot.items);
    } else {
      await _repository.updatePurchase(purchase, snapshot.items);
    }
  }

  Future<Never> _rollbackUnitOfWork({
    required String purchaseId,
    required _PurchaseSnapshot purchaseSnapshot,
    required List<PriceHistoryRecord>? historySnapshot,
    required _InventorySnapshot inventorySnapshot,
    required bool restorePurchase,
    required bool restoreHistory,
    required bool restoreInventory,
    required Object originalError,
    required StackTrace originalStackTrace,
  }) async {
    final rollbackErrors = <Object>[];
    if (restoreInventory) {
      try {
        inventorySnapshot.restore(_inventory);
        await _persistInventory?.call();
      } catch (error) {
        rollbackErrors.add(error);
      }
    }
    if (restoreHistory && historySnapshot != null) {
      try {
        await _priceHistory?.restorePurchaseSnapshot(
          purchaseId,
          historySnapshot,
        );
      } catch (error) {
        rollbackErrors.add(error);
      }
    }
    if (restorePurchase) {
      try {
        await _restorePurchaseSnapshot(purchaseId, purchaseSnapshot);
      } catch (error) {
        rollbackErrors.add(error);
      }
    }
    if (rollbackErrors.isNotEmpty) {
      throw PurchaseUnitOfWorkException(
        originalError: originalError,
        rollbackErrors: List.unmodifiable(rollbackErrors),
      );
    }
    Error.throwWithStackTrace(originalError, originalStackTrace);
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

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _newId(String prefix) {
    _idCounter++;
    return '${prefix}_${_clock().microsecondsSinceEpoch}_$_idCounter';
  }
}

class _PurchaseSnapshot {
  const _PurchaseSnapshot(this.purchase, this.items);

  final Purchase? purchase;
  final List<PurchaseItem> items;
}

class _InventorySnapshot {
  _InventorySnapshot._(this.items, this.itemStates, this.movements);

  factory _InventorySnapshot.capture(InventoryService inventory) {
    final items = inventory.items.toList(growable: false);
    return _InventorySnapshot._(
      items,
      {
        for (final item in items)
          item.id: PantryItem.fromJson(
            Map<String, dynamic>.from(item.toJson()),
          ),
      },
      inventory.movements
          .map(
            (movement) => PantryMovement.fromJson(
              Map<String, dynamic>.from(movement.toJson()),
            ),
          )
          .toList(growable: false),
    );
  }

  final List<PantryItem> items;
  final Map<String, PantryItem> itemStates;
  final List<PantryMovement> movements;

  void restore(InventoryService inventory) {
    for (final item in items) {
      final state = itemStates[item.id]!;
      item
        ..name = state.name
        ..category = state.category
        ..minimum = state.minimum
        ..unit = state.unit
        ..location = state.location
        ..primaryBarcode = state.primaryBarcode;
      item.additionalBarcodes
        ..clear()
        ..addAll(state.additionalBarcodes);
      item.batches
        ..clear()
        ..addAll(
          state.batches.map(
            (batch) => InventoryBatch.fromJson(
              Map<String, dynamic>.from(batch.toJson()),
            ),
          ),
        );
    }
    inventory.replaceState(
      items: items,
      movements: movements.map(
        (movement) => PantryMovement.fromJson(
          Map<String, dynamic>.from(movement.toJson()),
        ),
      ),
    );
  }
}

class PurchaseUnitOfWorkException implements Exception {
  const PurchaseUnitOfWorkException({
    required this.originalError,
    required this.rollbackErrors,
  });

  final Object originalError;
  final List<Object> rollbackErrors;

  @override
  String toString() =>
      'Purchase unit of work rollback failed: ${rollbackErrors.length} error(s).';
}

abstract interface class _QueuedPurchaseWrite {
  Future<void> run();
}

class _TypedQueuedPurchaseWrite<T> implements _QueuedPurchaseWrite {
  const _TypedQueuedPurchaseWrite(this.operation, this.completer);

  final Future<T> Function() operation;
  final Completer<T> completer;

  @override
  Future<void> run() async {
    try {
      completer.complete(await operation());
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }
}

class PurchaseValidationException implements Exception {
  const PurchaseValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PurchaseDeletionException implements Exception {
  const PurchaseDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}
