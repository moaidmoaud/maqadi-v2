import 'dart:collection';

import '../models/barcode_models.dart';
import '../models/dashboard_analytics_models.dart';
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
  int _analyticsRevision = 0;
  int _cachedAnalyticsRevision = -1;
  int _cachedShoppingListItems = -1;
  DateTime? _cachedAnalyticsDay;
  DashboardAnalytics? _cachedAnalytics;

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
    _invalidateAnalytics();
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
      final matchesQuery = normalizeArabic(
        item.name,
      ).contains(normalizedQuery);
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

  DashboardAnalytics dashboardAnalytics({required int shoppingListItems}) {
    final today = _dateOnly(_clock());
    final cached = _cachedAnalytics;
    if (cached != null &&
        _cachedAnalyticsRevision == _analyticsRevision &&
        _cachedShoppingListItems == shoppingListItems &&
        _cachedAnalyticsDay == today) {
      return cached;
    }

    var totalBatches = 0;
    var totalQuantity = 0.0;
    var lowStock = 0;
    var outOfStock = 0;
    var fresh = 0;
    var expiringSoon = 0;
    var expired = 0;
    final categories = <String, int>{};
    final insights = <ProductAnalyticsInsight>[];

    for (final item in _items) {
      final stock = stockInfoFor(item);
      totalQuantity += stock.currentQuantity;
      switch (stock.status) {
        case StockStatus.lowStock:
          lowStock++;
        case StockStatus.outOfStock:
          outOfStock++;
        case StockStatus.normalStock:
          break;
      }
      categories[item.category] = (categories[item.category] ?? 0) + 1;
      insights.add(_analyticsInsightFor(item));

      for (final batch in item.batches.where((batch) => batch.quantity > 0)) {
        totalBatches++;
        switch (expiryFor(item, batch).status) {
          case BatchExpiryStatus.fresh:
            fresh++;
          case BatchExpiryStatus.expiringSoon:
            expiringSoon++;
          case BatchExpiryStatus.expired:
            expired++;
        }
      }
    }

    final topProducts = List<ProductAnalyticsInsight>.from(insights)
      ..sort((a, b) {
        final byQuantity = b.quantity.compareTo(a.quantity);
        return byQuantity != 0
            ? byQuantity
            : a.item.name.compareTo(b.item.name);
      });
    final lowestStock = List<ProductAnalyticsInsight>.from(insights)
      ..sort((a, b) {
        final byQuantity = a.quantity.compareTo(b.quantity);
        return byQuantity != 0
            ? byQuantity
            : a.item.name.compareTo(b.item.name);
      });
    final recentlyUpdated = List<ProductAnalyticsInsight>.from(insights)
      ..sort((a, b) {
        final byDate = _compareRecentDates(a.updatedAt, b.updatedAt);
        return byDate != 0 ? byDate : a.item.name.compareTo(b.item.name);
      });
    final recentlyAdded = List<ProductAnalyticsInsight>.from(insights)
      ..sort((a, b) {
        final byDate = _compareRecentDates(a.addedAt, b.addedAt);
        return byDate != 0 ? byDate : a.item.name.compareTo(b.item.name);
      });
    final categoryDistribution = categories.entries
        .map(
          (entry) =>
              AnalyticsDistribution(label: entry.key, value: entry.value),
        )
        .toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.label.compareTo(b.label);
      });

    final analytics = DashboardAnalytics(
      summary: DashboardSummary(
        totalProducts: _items.length,
        totalBatches: totalBatches,
        totalQuantity: totalQuantity,
        lowStock: lowStock,
        outOfStock: outOfStock,
        expiringSoon: expiringSoon,
        expired: expired,
        shoppingListItems: shoppingListItems,
      ),
      topProducts: List.unmodifiable(topProducts.take(10)),
      lowestStockProducts: List.unmodifiable(lowestStock.take(10)),
      recentlyUpdatedProducts: List.unmodifiable(recentlyUpdated.take(10)),
      recentlyAddedProducts: List.unmodifiable(recentlyAdded.take(10)),
      stockStatusDistribution: List.unmodifiable([
        AnalyticsDistribution(
          label: 'طبيعي',
          value: _items.length - lowStock - outOfStock,
        ),
        AnalyticsDistribution(label: 'منخفض', value: lowStock),
        AnalyticsDistribution(label: 'نافد', value: outOfStock),
      ]),
      expiryStatusDistribution: List.unmodifiable([
        AnalyticsDistribution(label: 'طازج', value: fresh),
        AnalyticsDistribution(
            label: 'قريبة خلال 30 يومًا', value: expiringSoon),
        AnalyticsDistribution(label: 'منتهية', value: expired),
      ]),
      categoryDistribution: List.unmodifiable(categoryDistribution),
    );
    _cachedAnalytics = analytics;
    _cachedAnalyticsRevision = _analyticsRevision;
    _cachedShoppingListItems = shoppingListItems;
    _cachedAnalyticsDay = today;
    return analytics;
  }

  List<DashboardSearchResult> searchDashboard(String query) {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return const [];
    final results = <DashboardSearchResult>[];
    for (final item in _items) {
      final normalizedName = normalizeArabic(item.name);
      final normalizedCategory = normalizeArabic(item.category);
      final barcodeValues = <String>[
        if (item.primaryBarcode != null) item.primaryBarcode!,
        ...item.additionalBarcodes,
      ];
      final normalizedBarcodes = {
        for (final barcode in barcodeValues) barcode: normalizeArabic(barcode),
      };
      final normalizedBatchIds = {
        for (final batch in item.batches) batch.id: normalizeArabic(batch.id),
      };
      final searchable = [
        normalizedName,
        normalizedCategory,
        ...normalizedBarcodes.values,
        ...normalizedBatchIds.values,
      ].join(' ');
      if (!tokens.every(searchable.contains)) continue;

      final matchedFields = <String>[];
      if (tokens.any(normalizedName.contains)) matchedFields.add('اسم المنتج');
      if (tokens.any(normalizedCategory.contains)) {
        matchedFields.add('التصنيف');
      }
      final matchedBarcodes = normalizedBarcodes.entries
          .where((entry) => tokens.every(entry.value.contains))
          .map((entry) => entry.key)
          .toList()
        ..sort();
      if (matchedBarcodes.isNotEmpty) matchedFields.add('الباركود');
      final matchedBatchIds = normalizedBatchIds.entries
          .where((entry) => tokens.every(entry.value.contains))
          .map((entry) => entry.key)
          .toList()
        ..sort();
      if (matchedBatchIds.isNotEmpty) matchedFields.add('معرّف الدفعة');
      results.add(
        DashboardSearchResult(
          item: item,
          matchedFields: List.unmodifiable(matchedFields),
          matchedBarcodes: List.unmodifiable(matchedBarcodes),
          matchedBatchIds: List.unmodifiable(matchedBatchIds),
        ),
      );
    }
    results.sort((a, b) {
      final byRank = _dashboardSearchRank(
        a.item,
        tokens,
      ).compareTo(_dashboardSearchRank(b.item, tokens));
      return byRank != 0 ? byRank : a.item.name.compareTo(b.item.name);
    });
    return List.unmodifiable(results.take(20));
  }

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
    _recordMovement(
      item,
      'تعديل دفعة',
      delta,
      note: batch.note,
      batchAllocations: delta == 0 ? const {} : {resolvedId: delta},
    );
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
    final detailsChanged = item.name != name ||
        item.category != category ||
        item.minimum != minimum.clamp(0, 999999).toDouble() ||
        item.unit != unit ||
        item.location != location;
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
    } else if (detailsChanged) {
      _recordMovement(item, 'تحديث بيانات', 0);
    }
  }

  PantryItem? findByName(String name) {
    final normalized = normalizeArabic(name);
    for (final item in _items) {
      if (normalizeArabic(item.name) == normalized) return item;
    }
    return null;
  }

  PantryItem? findByBarcode(String barcode) {
    final key = _barcodeKey(barcode);
    if (key.isEmpty) return null;
    for (final item in _items) {
      if (_barcodeKey(item.primaryBarcode ?? '') == key ||
          item.additionalBarcodes.any((value) => _barcodeKey(value) == key)) {
        return item;
      }
    }
    return null;
  }

  void validateBarcodes({
    PantryItem? item,
    String? primaryBarcode,
    Iterable<String> additionalBarcodes = const [],
  }) {
    final values = <String>[
      if (_cleanBarcode(primaryBarcode) case final primary?) primary,
      for (final value in additionalBarcodes)
        if (_cleanBarcode(value) case final additional?) additional,
    ];
    for (final barcode in values) {
      final owner = findByBarcode(barcode);
      if (owner != null && !identical(owner, item)) {
        throw ArgumentError.value(
          barcode,
          'barcode',
          'الباركود مرتبط بالمنتج ${owner.name}',
        );
      }
    }
  }

  bool setBarcodes(
    PantryItem item, {
    String? primaryBarcode,
    Iterable<String> additionalBarcodes = const [],
  }) {
    _requireItem(item);
    final primary = _cleanBarcode(primaryBarcode);
    final additionalByKey = <String, String>{};
    for (final value in additionalBarcodes) {
      final clean = _cleanBarcode(value);
      if (clean == null || _barcodeKey(clean) == _barcodeKey(primary ?? '')) {
        continue;
      }
      additionalByKey.putIfAbsent(_barcodeKey(clean), () => clean);
    }
    validateBarcodes(
      item: item,
      primaryBarcode: primary,
      additionalBarcodes: additionalByKey.values,
    );
    final unchanged = item.primaryBarcode == primary &&
        _sameBarcodeList(item.additionalBarcodes, additionalByKey.values);
    if (unchanged) return false;
    item.primaryBarcode = primary;
    item.additionalBarcodes
      ..clear()
      ..addAll(additionalByKey.values);
    _recordMovement(item, 'تحديث باركود', 0);
    return true;
  }

  bool addBarcode(
    PantryItem item,
    String barcode, {
    bool makePrimary = false,
  }) {
    _requireItem(item);
    final clean = _cleanBarcode(barcode);
    if (clean == null) {
      throw ArgumentError.value(barcode, 'barcode', 'الباركود فارغ');
    }
    final owner = findByBarcode(clean);
    if (owner != null) {
      if (identical(owner, item)) return false;
      throw ArgumentError.value(
        barcode,
        'barcode',
        'الباركود مرتبط بالمنتج ${owner.name}',
      );
    }
    final oldPrimary = item.primaryBarcode;
    if (makePrimary || oldPrimary == null) {
      return setBarcodes(
        item,
        primaryBarcode: clean,
        additionalBarcodes: [
          if (oldPrimary != null) oldPrimary,
          ...item.additionalBarcodes,
        ],
      );
    }
    return setBarcodes(
      item,
      primaryBarcode: oldPrimary,
      additionalBarcodes: [...item.additionalBarcodes, clean],
    );
  }

  bool makePrimaryBarcode(PantryItem item, String barcode) {
    _requireItem(item);
    final clean = _cleanBarcode(barcode);
    if (clean == null || !identical(findByBarcode(clean), item)) return false;
    final currentPrimary = item.primaryBarcode;
    if (_barcodeKey(currentPrimary ?? '') == _barcodeKey(clean)) return false;
    return setBarcodes(
      item,
      primaryBarcode: clean,
      additionalBarcodes: [
        if (currentPrimary != null) currentPrimary,
        ...item.additionalBarcodes.where(
          (value) => _barcodeKey(value) != _barcodeKey(clean),
        ),
      ],
    );
  }

  bool removeBarcode(PantryItem item, String barcode) {
    _requireItem(item);
    final key = _barcodeKey(barcode);
    if (key.isEmpty || !identical(findByBarcode(barcode), item)) return false;
    return setBarcodes(
      item,
      primaryBarcode: _barcodeKey(item.primaryBarcode ?? '') == key
          ? null
          : item.primaryBarcode,
      additionalBarcodes: item.additionalBarcodes.where(
        (value) => _barcodeKey(value) != key,
      ),
    );
  }

  String productQrPayload(PantryItem item) {
    _requireItem(item);
    return Uri(
      scheme: 'maqadi',
      host: 'product',
      pathSegments: [item.id],
    ).toString();
  }

  String batchQrPayload(PantryItem item, InventoryBatch batch) {
    _requireBatch(item, batch);
    return Uri(
      scheme: 'maqadi',
      host: 'product',
      pathSegments: [item.id, 'batch', batch.id],
    ).toString();
  }

  InventoryQrTarget? resolveInternalQr(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'maqadi' || uri.host != 'product') {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.isEmpty) return null;
    final item = _findById(segments.first);
    if (item == null) return null;
    if (segments.length == 1) return InventoryQrTarget(item: item);
    if (segments.length != 3 || segments[1] != 'batch') return null;
    for (final batch in item.batches) {
      if (batch.id == segments[2]) {
        return InventoryQrTarget(item: item, batch: batch);
      }
    }
    return null;
  }

  InventoryScanResult resolveScan(String rawValue) {
    final value = rawValue.trim();
    final qrTarget = resolveInternalQr(value);
    if (qrTarget != null) {
      return InventoryScanResult(
        type: InventoryScanResultType.internalQr,
        rawValue: value,
        item: qrTarget.item,
        batch: qrTarget.batch,
      );
    }
    final barcodeItem = findByBarcode(value);
    if (barcodeItem != null) {
      return InventoryScanResult(
        type: InventoryScanResultType.barcode,
        rawValue: value,
        item: barcodeItem,
      );
    }
    return InventoryScanResult(
      type: InventoryScanResultType.unknown,
      rawValue: value,
    );
  }

  ProductAnalyticsInsight _analyticsInsightFor(PantryItem item) {
    DateTime? addedAt;
    DateTime? updatedAt;
    for (final movement in _movements) {
      if (movement.pantryItemId != item.id) continue;
      if (addedAt == null || movement.createdAt.isBefore(addedAt)) {
        addedAt = movement.createdAt;
      }
      if (updatedAt == null || movement.createdAt.isAfter(updatedAt)) {
        updatedAt = movement.createdAt;
      }
    }
    if (addedAt == null || updatedAt == null) {
      for (final batch in item.batches) {
        if (addedAt == null || batch.receivedAt.isBefore(addedAt)) {
          addedAt = batch.receivedAt;
        }
        if (updatedAt == null || batch.receivedAt.isAfter(updatedAt)) {
          updatedAt = batch.receivedAt;
        }
      }
    }
    return ProductAnalyticsInsight(
      item: item,
      quantity: item.quantity,
      addedAt: addedAt,
      updatedAt: updatedAt,
    );
  }

  int _compareRecentDates(DateTime? a, DateTime? b) {
    if (a == null || b == null) {
      if (a == null && b == null) return 0;
      return a == null ? 1 : -1;
    }
    return b.compareTo(a);
  }

  int _dashboardSearchRank(PantryItem item, List<String> tokens) {
    final name = normalizeArabic(item.name);
    if (tokens.every(name.contains)) return 0;
    final category = normalizeArabic(item.category);
    if (tokens.every(category.contains)) return 1;
    final barcodes = [
      if (item.primaryBarcode != null) item.primaryBarcode!,
      ...item.additionalBarcodes,
    ];
    if (barcodes.any((barcode) {
      final key = normalizeArabic(barcode);
      return tokens.every(key.contains);
    })) {
      return 2;
    }
    if (item.batches.any((batch) {
      final id = normalizeArabic(batch.id);
      return tokens.every(id.contains);
    })) {
      return 3;
    }
    return 4;
  }

  String? _cleanBarcode(String? value) {
    final clean = value?.trim().replaceAll(RegExp(r'\s+'), '') ?? '';
    return clean.isEmpty ? null : clean;
  }

  String _barcodeKey(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();

  bool _sameBarcodeList(Iterable<String> a, Iterable<String> b) {
    final aKeys = a.map(_barcodeKey).toList();
    final bKeys = b.map(_barcodeKey).toList();
    if (aKeys.length != bKeys.length) return false;
    for (var index = 0; index < aKeys.length; index++) {
      if (aKeys[index] != bKeys[index]) return false;
    }
    return true;
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
    _invalidateAnalytics();
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
    _invalidateAnalytics();
  }

  void _invalidateAnalytics() {
    _analyticsRevision++;
    _cachedAnalytics = null;
  }

  String _newId() {
    final idFactory = _idFactory;
    if (idFactory != null) return idFactory();
    _idCounter++;
    return '${_clock().microsecondsSinceEpoch}_$_idCounter';
  }
}
