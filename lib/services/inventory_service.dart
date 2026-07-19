import 'dart:collection';

import '../models/expiry_models.dart';
import '../models/inventory_models.dart';
import '../models/shopping_models.dart';
import '../models/stock_models.dart';
import '../utils/arabic_text.dart';

typedef InventoryClock = DateTime Function();
typedef InventoryIdFactory = String Function();

class InventoryService {
  InventoryService({
    List<PantryItem>? items,
    List<PantryMovement>? movements,
    InventoryClock? clock,
    InventoryIdFactory? idFactory,
  })  : _items = items ?? [],
        _movements = movements ?? [],
        _clock = clock ?? DateTime.now,
        _idFactory = idFactory;

  final List<PantryItem> _items;
  final List<PantryMovement> _movements;
  final InventoryClock _clock;
  final InventoryIdFactory? _idFactory;
  int _idCounter = 0;

  UnmodifiableListView<PantryItem> get items => UnmodifiableListView(_items);

  UnmodifiableListView<PantryMovement> get movements =>
      UnmodifiableListView(_movements);

  void replaceState({
    required Iterable<PantryItem> items,
    required Iterable<PantryMovement> movements,
  }) {
    _items
      ..clear()
      ..addAll(items);
    _movements
      ..clear()
      ..addAll(movements);
  }

  List<PantryItem> get lowStockItems {
    return stockItems(StockStatus.lowStock).map((info) => info.item).toList();
  }

  List<PantryItem> get emptyItems {
    return stockItems(StockStatus.outOfStock).map((info) => info.item).toList();
  }

  List<PantryItem> get healthyItems {
    return stockItems(
      StockStatus.normalStock,
    ).map((info) => info.item).toList();
  }

  StockInfo stockInfoFor(PantryItem item) {
    _requireItem(item);
    final quantity = item.quantity;
    final status = quantity <= 0
        ? StockStatus.outOfStock
        : quantity <= item.minimum
            ? StockStatus.lowStock
            : StockStatus.normalStock;
    return StockInfo(
      item: item,
      status: status,
      currentQuantity: quantity,
      minimumQuantity: item.minimum,
    );
  }

  List<StockInfo> stockItems(StockStatus status, {String query = ''}) {
    final normalizedQuery = normalizeArabic(query);
    final result = _items
        .map(stockInfoFor)
        .where((info) => info.status == status)
        .where(
          (info) =>
              normalizedQuery.isEmpty ||
              [info.item.name, info.item.category, info.item.location].any(
                (value) => normalizeArabic(value).contains(normalizedQuery),
              ),
        )
        .toList()
      ..sort((a, b) => a.item.name.compareTo(b.item.name));
    return List.unmodifiable(result);
  }

  List<PantryItem> pantryItems({
    String query = '',
    String? location,
    bool needsShoppingOnly = false,
  }) {
    final normalizedQuery = normalizeArabic(query);
    final result = _items.where((item) {
      final info = stockInfoFor(item);
      final matchesQuery = normalizeArabic(item.name).contains(normalizedQuery);
      final matchesLocation = location == null || item.location == location;
      final matchesStatus =
          !needsShoppingOnly || info.status != StockStatus.normalStock;
      return matchesQuery && matchesLocation && matchesStatus;
    }).toList()
      ..sort((a, b) {
        final byStatus = _stockSortOrder(
          stockInfoFor(a).status,
        ).compareTo(_stockSortOrder(stockInfoFor(b).status));
        return byStatus != 0 ? byStatus : a.name.compareTo(b.name);
      });
    return List.unmodifiable(result);
  }

  List<GroceryItem> shoppingItemsFor(
    ShoppingListModel list, {
    String query = '',
    StockStatus? stockStatus,
    bool hideDone = false,
  }) {
    final normalizedQuery = normalizeArabic(query);
    final result = list.items.where((grocery) {
      if (hideDone && grocery.done) return false;
      if (normalizedQuery.isNotEmpty &&
          !normalizeArabic(
            '${grocery.name} ${grocery.category}',
          ).contains(normalizedQuery)) {
        return false;
      }
      if (stockStatus == null) return true;
      final pantryItem = _pantryItemFor(grocery);
      return pantryItem != null &&
          stockInfoFor(pantryItem).status == stockStatus;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(result);
  }

  StockInfo? stockInfoForGrocery(GroceryItem grocery) {
    final item = _pantryItemFor(grocery);
    return item == null ? null : stockInfoFor(item);
  }

  bool synchronizeAutomaticShoppingList(
    ShoppingListModel list, {
    required String Function() idFactory,
  }) {
    var changed = false;
    final manualNames = list.items
        .where((grocery) => grocery.pantryItemId == null)
        .map((grocery) => normalizeArabic(grocery.name))
        .toSet();
    final seenPantryIds = <String>{};

    list.items.removeWhere((grocery) {
      final pantryItemId = grocery.pantryItemId;
      if (pantryItemId == null) return false;
      final pantryItem = _findById(pantryItemId);
      final remove = pantryItem == null ||
          stockInfoFor(pantryItem).status == StockStatus.normalStock ||
          manualNames.contains(normalizeArabic(pantryItem.name)) ||
          !seenPantryIds.add(pantryItemId);
      if (remove) changed = true;
      return remove;
    });

    final needsShopping = [
      ...stockItems(StockStatus.outOfStock),
      ...stockItems(StockStatus.lowStock),
    ];
    for (final info in needsShopping) {
      final item = info.item;
      if (manualNames.contains(normalizeArabic(item.name))) continue;
      GroceryItem? automatic;
      for (final grocery in list.items) {
        if (grocery.pantryItemId == item.id) {
          automatic = grocery;
          break;
        }
      }
      final quantity = recommendedShoppingQuantity(item);
      if (automatic == null) {
        list.items.add(
          GroceryItem(
            id: idFactory(),
            name: item.name,
            category: item.category,
            quantity: quantity,
            pantryItemId: item.id,
          ),
        );
        changed = true;
      } else {
        if (automatic.name != item.name ||
            automatic.category != item.category ||
            automatic.quantity != quantity) {
          automatic
            ..name = item.name
            ..category = item.category
            ..quantity = quantity;
          changed = true;
        }
      }
    }
    return changed;
  }

  int recommendedShoppingQuantity(PantryItem item) {
    _requireItem(item);
    final quantity = (item.minimum - item.quantity).floor() + 1;
    return quantity.clamp(1, 999).toInt();
  }

  bool removeAutomaticShoppingItems(ShoppingListModel list) {
    final before = list.items.length;
    list.items.removeWhere((grocery) => grocery.pantryItemId != null);
    return before != list.items.length;
  }

  List<PantryMovement> movementsFor(PantryItem item) {
    final result = _movements
        .where((movement) => movement.pantryItemId == item.id)
        .toList();
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  List<InventoryBatch> batchesFor(PantryItem item) {
    _requireItem(item);
    final result = item.batches.where((batch) => batch.quantity > 0).toList()
      ..sort(_compareBatches);
    return List.unmodifiable(result);
  }

  BatchExpiryInfo expiryFor(PantryItem item, InventoryBatch batch) {
    _requireBatch(item, batch);
    final daysRemaining = _daysRemaining(batch);
    return BatchExpiryInfo(
      item: item,
      batch: batch,
      status: _expiryStatus(daysRemaining),
      daysRemaining: daysRemaining,
    );
  }

  List<BatchExpiryInfo> expiryBatches(
    BatchExpiryStatus status, {
    String query = '',
  }) {
    final normalizedQuery = normalizeArabic(query);
    final result = <BatchExpiryInfo>[];
    for (final item in _items) {
      for (final batch in item.batches.where((batch) => batch.quantity > 0)) {
        final info = expiryFor(item, batch);
        if (info.status != status) continue;
        if (normalizedQuery.isNotEmpty &&
            !_matchesExpiryQuery(item, batch, normalizedQuery)) {
          continue;
        }
        result.add(info);
      }
    }
    result.sort(_compareNearestExpiry);
    return List.unmodifiable(result);
  }

  List<BatchExpiryInfo> expiringSoonBatches({String query = ''}) =>
      expiryBatches(BatchExpiryStatus.expiringSoon, query: query);

  List<BatchExpiryInfo> expiredBatches({String query = ''}) =>
      expiryBatches(BatchExpiryStatus.expired, query: query);

  PantryItem addStock({
    required String name,
    required String category,
    required double quantity,
    required double minimum,
    required String unit,
    required String location,
    String movementType = 'إضافة',
    String? note,
    DateTime? receivedAt,
    DateTime? expiresAt,
    bool updateExistingDetails = true,
  }) {
    final cleanQuantity = quantity.clamp(0, 999999).toDouble();
    final item = findByName(name) ??
        PantryItem(
          id: _newId(),
          name: name,
          category: category,
          minimum: minimum,
          unit: unit,
          location: location,
        );

    if (!_items.contains(item)) _items.add(item);
    if (updateExistingDetails) {
      item
        ..category = category
        ..minimum = minimum
        ..unit = unit
        ..location = location;
    }

    final allocations = <String, double>{};
    if (cleanQuantity > 0) {
      final batch = _appendBatch(
        item,
        cleanQuantity,
        receivedAt: receivedAt,
        expiresAt: expiresAt,
        note: note,
      );
      allocations[batch.id] = cleanQuantity;
    }
    _recordMovement(
      item,
      movementType,
      cleanQuantity,
      note: note,
      batchAllocations: allocations,
    );
    return item;
  }

  InventoryBatch addBatch(
    PantryItem item, {
    required double quantity,
    DateTime? receivedAt,
    DateTime? expiresAt,
    String? batchId,
    String? note,
    String movementType = 'إضافة',
  }) {
    final cleanQuantity = quantity.clamp(0, 999999).toDouble();
    if (cleanQuantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'يجب أن تكون الكمية أكبر من صفر',
      );
    }
    _requireItem(item);
    final batch = _appendBatch(
      item,
      cleanQuantity,
      id: _resolveBatchId(item, batchId),
      receivedAt: receivedAt,
      expiresAt: expiresAt,
      note: note,
    );
    _recordMovement(
      item,
      movementType,
      cleanQuantity,
      note: note,
      batchAllocations: {batch.id: cleanQuantity},
    );
    return batch;
  }

  void updateBatch(
    PantryItem item,
    InventoryBatch batch, {
    required double quantity,
    required DateTime receivedAt,
    DateTime? expiresAt,
    String? batchId,
    String? note,
  }) {
    _requireBatch(item, batch);
    final cleanQuantity = quantity.clamp(0, 999999).toDouble();
    if (cleanQuantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'يجب أن تكون الكمية أكبر من صفر',
      );
    }
    final previousQuantity = batch.quantity;
    final resolvedId = _resolveBatchId(item, batchId, currentBatch: batch);

    batch
      ..id = resolvedId
      ..quantity = cleanQuantity
      ..receivedAt = receivedAt
      ..expiresAt = expiresAt
      ..note = _cleanOptionalText(note);

    final delta = cleanQuantity - previousQuantity;
    if (delta != 0) {
      _recordMovement(
        item,
        'تعديل دفعة',
        delta,
        note: batch.note,
        batchAllocations: {resolvedId: delta},
      );
    }
  }

  void deleteBatch(PantryItem item, InventoryBatch batch) {
    _requireBatch(item, batch);
    final removedQuantity = batch.quantity;
    final batchId = batch.id;
    final note = batch.note;
    item.batches.remove(batch);
    if (removedQuantity > 0) {
      _recordMovement(
        item,
        'حذف دفعة',
        -removedQuantity,
        note: note,
        batchAllocations: {batchId: -removedQuantity},
      );
    }
  }

  double consume(
    PantryItem item,
    double quantity, {
    String movementType = 'استهلاك',
    String? note,
  }) {
    final requested = quantity.clamp(0, 999999).toDouble();
    final allocations = _consumeFifo(item, requested);
    final consumed = allocations.values.fold<double>(0, (sum, value) {
      return sum + value.abs();
    });
    if (consumed > 0) {
      _recordMovement(
        item,
        movementType,
        -consumed,
        note: note,
        batchAllocations: allocations,
      );
    }
    return consumed;
  }

  double changeQuantity(PantryItem item, double delta) {
    if (delta == 0) return 0;
    if (delta < 0) return -consume(item, -delta);

    final batch = _appendBatch(item, delta);
    _recordMovement(
      item,
      'إضافة',
      batch.quantity,
      batchAllocations: {batch.id: batch.quantity},
    );
    return batch.quantity;
  }

  void updateItem(
    PantryItem item, {
    required String name,
    required String category,
    required double quantity,
    required double minimum,
    required String unit,
    required String location,
  }) {
    item
      ..name = name
      ..category = category
      ..minimum = minimum.clamp(0, 999999).toDouble()
      ..unit = unit
      ..location = location;

    final targetQuantity = quantity.clamp(0, 999999).toDouble();
    final delta = targetQuantity - item.quantity;
    if (delta > 0) {
      final batch = _appendBatch(item, delta, note: 'تعديل الرصيد');
      _recordMovement(
        item,
        'تعديل',
        delta,
        batchAllocations: {batch.id: delta},
      );
    } else if (delta < 0) {
      final allocations = _consumeFifo(item, -delta);
      final actual = allocations.values.fold<double>(0, (sum, value) {
        return sum + value.abs();
      });
      if (actual > 0) {
        _recordMovement(item, 'تعديل', -actual, batchAllocations: allocations);
      }
    }
  }

  PantryItem? findByName(String name) {
    final normalized = normalizeArabic(name);
    for (final item in _items) {
      if (normalizeArabic(item.name) == normalized) return item;
    }
    return null;
  }

  PantryItem? _pantryItemFor(GroceryItem grocery) {
    final pantryItemId = grocery.pantryItemId;
    if (pantryItemId != null) return _findById(pantryItemId);
    return findByName(grocery.name);
  }

  PantryItem? _findById(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  int _stockSortOrder(StockStatus status) => switch (status) {
        StockStatus.outOfStock => 0,
        StockStatus.lowStock => 1,
        StockStatus.normalStock => 2,
      };

  void deleteItem(PantryItem item) {
    _items.remove(item);
    _movements.removeWhere((movement) => movement.pantryItemId == item.id);
  }

  InventoryBatch _appendBatch(
    PantryItem item,
    double quantity, {
    String? id,
    DateTime? receivedAt,
    DateTime? expiresAt,
    String? note,
  }) {
    final batch = InventoryBatch(
      id: id ?? _resolveBatchId(item, null),
      quantity: quantity.clamp(0, 999999).toDouble(),
      receivedAt: receivedAt ?? _clock(),
      expiresAt: expiresAt,
      note: _cleanOptionalText(note),
    );
    item.batches.add(batch);
    return batch;
  }

  Map<String, double> _consumeFifo(PantryItem item, double quantity) {
    var remaining = quantity;
    final allocations = <String, double>{};
    final ordered = item.batches.where((batch) => batch.quantity > 0).toList()
      ..sort(_compareBatches);

    for (final batch in ordered) {
      if (remaining <= 0) break;
      final consumed = remaining < batch.quantity ? remaining : batch.quantity;
      batch.quantity -= consumed;
      remaining -= consumed;
      allocations[batch.id] = -consumed;
    }
    item.batches.removeWhere((batch) => batch.quantity <= 0);
    return allocations;
  }

  int _compareBatches(InventoryBatch a, InventoryBatch b) {
    final byDate = a.receivedAt.compareTo(b.receivedAt);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }

  int? _daysRemaining(InventoryBatch batch) {
    final expiresAt = batch.expiresAt;
    if (expiresAt == null) return null;
    return _dateOnly(expiresAt).difference(_dateOnly(_clock())).inDays;
  }

  BatchExpiryStatus _expiryStatus(int? daysRemaining) {
    if (daysRemaining == null || daysRemaining > 30) {
      return BatchExpiryStatus.fresh;
    }
    if (daysRemaining < 0) return BatchExpiryStatus.expired;
    return BatchExpiryStatus.expiringSoon;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  bool _matchesExpiryQuery(
    PantryItem item,
    InventoryBatch batch,
    String normalizedQuery,
  ) {
    return [
      item.name,
      item.category,
      item.location,
      batch.id,
      batch.note ?? '',
    ].any((value) => normalizeArabic(value).contains(normalizedQuery));
  }

  int _compareNearestExpiry(BatchExpiryInfo a, BatchExpiryInfo b) {
    final aDays = a.daysRemaining;
    final bDays = b.daysRemaining;
    if (aDays == null || bDays == null) {
      if (aDays == null && bDays == null) return 0;
      return aDays == null ? 1 : -1;
    }
    final byDistance = aDays.abs().compareTo(bDays.abs());
    if (byDistance != 0) return byDistance;
    final byExpiry = a.batch.expiresAt!.compareTo(b.batch.expiresAt!);
    if (byExpiry != 0) return byExpiry;
    final byProduct = a.item.name.compareTo(b.item.name);
    return byProduct != 0 ? byProduct : a.batch.id.compareTo(b.batch.id);
  }

  String _resolveBatchId(
    PantryItem item,
    String? requestedId, {
    InventoryBatch? currentBatch,
  }) {
    final requested = requestedId?.trim() ?? '';
    if (requested.isNotEmpty) {
      final duplicate = item.batches.any(
        (batch) => !identical(batch, currentBatch) && batch.id == requested,
      );
      if (duplicate) {
        throw ArgumentError.value(
          requestedId,
          'batchId',
          'معرّف الدفعة مستخدم لهذا المنتج',
        );
      }
      return requested;
    }

    String generated;
    do {
      generated = _newId();
    } while (item.batches.any((batch) => batch.id == generated));
    return generated;
  }

  void _requireItem(PantryItem item) {
    if (!_items.contains(item)) {
      throw ArgumentError.value(item, 'item', 'المنتج غير موجود في المخزون');
    }
  }

  void _requireBatch(PantryItem item, InventoryBatch batch) {
    _requireItem(item);
    if (!item.batches.contains(batch)) {
      throw ArgumentError.value(
        batch,
        'batch',
        'الدفعة غير مرتبطة بهذا المنتج',
      );
    }
  }

  String? _cleanOptionalText(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }

  void _recordMovement(
    PantryItem item,
    String type,
    double amount, {
    String? note,
    Map<String, double> batchAllocations = const {},
  }) {
    _movements.add(
      PantryMovement(
        id: _newId(),
        pantryItemId: item.id,
        productName: item.name,
        type: type,
        amount: amount,
        unit: item.unit,
        createdAt: _clock(),
        note: note,
        batchAllocations: batchAllocations,
      ),
    );
  }

  String _newId() {
    final idFactory = _idFactory;
    if (idFactory != null) return idFactory();
    _idCounter++;
    return '${_clock().microsecondsSinceEpoch}_$_idCounter';
  }
}
