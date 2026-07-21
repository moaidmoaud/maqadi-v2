import 'dart:async';

import 'package:flutter/material.dart';

import 'consumption/application/consumption_service.dart';
import 'consumption/engine/consumption_engine.dart';
import 'consumption/infrastructure/inventory_service_consumption_reader.dart';
import 'inventory_health/application/inventory_health_service.dart';
import 'inventory_health/engine/inventory_health_engine.dart';
import 'inventory_health/infrastructure/inventory_service_health_reader.dart';
import 'models/barcode_models.dart';
import 'models/dashboard_analytics_models.dart';
import 'models/expiry_models.dart';
import 'models/inventory_models.dart';
import 'models/notification_models.dart';
import 'models/report_models.dart';
import 'models/shopping_models.dart';
import 'models/stock_models.dart';
import 'products.dart';
import 'repositories/app_repository.dart';
import 'repositories/price_history_repository.dart';
import 'repositories/purchase_repository.dart';
import 'repositories/shared_preferences_app_repository.dart';
import 'repositories/shared_preferences_price_history_repository.dart';
import 'repositories/shared_preferences_purchase_repository.dart';
import 'repositories/shared_preferences_store_repository.dart';
import 'repositories/store_repository.dart';
import 'services/inventory_service.dart';
import 'services/local_notification_scheduler.dart';
import 'services/notification_scheduler.dart';
import 'services/price_history_service.dart';
import 'services/purchase_service.dart';
import 'services/report_delivery.dart';
import 'services/report_service.dart';
import 'services/store_service.dart';
import 'utils/arabic_text.dart';

class AppStore extends ChangeNotifier {
  AppStore({
    AppRepository? repository,
    PriceHistoryRepository? priceHistoryRepository,
    PriceHistoryService? priceHistoryService,
    PurchaseRepository? purchaseRepository,
    PurchaseService? purchaseService,
    StoreRepository? storeRepository,
    StoreService? storeService,
    InventoryService? inventoryService,
    InventoryHealthService? inventoryHealthService,
    ConsumptionService? consumptionService,
    NotificationScheduler? notificationScheduler,
    ReportGenerator? reportGenerator,
    ReportDelivery? reportDelivery,
  })  : _repository = repository ?? SharedPreferencesAppRepository(),
        _purchaseRepository =
            purchaseRepository ?? SharedPreferencesPurchaseRepository(),
        _inventory = inventoryService ?? InventoryService(),
        _notificationScheduler =
            notificationScheduler ?? LocalNotificationScheduler() {
    _reportGenerator =
        reportGenerator ?? ReportService(inventoryService: _inventory);
    _reportDelivery = reportDelivery ?? const PlatformReportDelivery();
    _priceHistoryService = priceHistoryService ??
        PriceHistoryService(
          repository: priceHistoryRepository ??
              SharedPreferencesPriceHistoryRepository(),
        );
    _storeService = storeService ??
        StoreService(
          repository: storeRepository ?? SharedPreferencesStoreRepository(),
          purchaseRepository: _purchaseRepository,
        );
    _purchaseService = purchaseService ??
        PurchaseService(
          repository: _purchaseRepository,
          inventoryService: _inventory,
          priceHistoryService: _priceHistoryService,
          storeService: _storeService,
          persistInventory: _persistPurchaseInventory,
        );
    _inventoryHealthService = inventoryHealthService ??
        InventoryHealthService(
          inputReader: InventoryServiceHealthReader(_inventory),
          engine: const InventoryHealthEngine(),
        );
    _consumptionService = consumptionService ??
        ConsumptionService(
          inputReader: InventoryServiceConsumptionReader(_inventory),
          engine: const ConsumptionEngine(),
        );
  }

  final AppRepository _repository;
  final PurchaseRepository _purchaseRepository;
  final InventoryService _inventory;
  final NotificationScheduler _notificationScheduler;
  late final ReportGenerator _reportGenerator;
  late final ReportDelivery _reportDelivery;
  late final PriceHistoryService _priceHistoryService;
  late final PurchaseService _purchaseService;
  late final StoreService _storeService;
  late final InventoryHealthService _inventoryHealthService;
  late final ConsumptionService _consumptionService;
  final List<ShoppingListModel> lists = [];
  final Set<String> favorites = {};
  final Map<String, int> frequency = {};
  String? lastListId;
  ThemeMode themeMode = ThemeMode.system;
  double fontScale = 1;
  NotificationSettings notificationSettings = const NotificationSettings();
  bool isReady = false;
  Timer? _saveTimer;
  int _idCounter = 0;

  List<PantryItem> get pantry => _inventory.items;
  List<PantryMovement> get pantryMovements => _inventory.movements;
  List<String> get reportCategories => _reportGenerator.categories;
  PriceHistoryService get priceHistoryService => _priceHistoryService;
  PurchaseService get purchaseService => _purchaseService;
  StoreService get storeService => _storeService;
  InventoryHealthService get inventoryHealthService => _inventoryHealthService;
  ConsumptionService get consumptionService => _consumptionService;
  PantryItem? pantryItemById(String id) => _inventory.findById(id);

  Future<GeneratedReportFile> generatePdfReport(
    PdfReportType type, {
    ReportFilter filter = const ReportFilter(),
  }) =>
      _reportGenerator.generatePdf(
        type,
        filter: filter,
        shoppingItems: lastList?.items ?? const [],
      );

  GeneratedReportFile generateExcelReport({
    ReportFilter filter = const ReportFilter(),
  }) =>
      _reportGenerator.generateExcel(
        filter: filter,
        shoppingItems: lastList?.items ?? const [],
      );

  GeneratedReportFile generateCsvReport(
    CsvReportType type, {
    ReportFilter filter = const ReportFilter(),
  }) =>
      _reportGenerator.generateCsv(
        type,
        filter: filter,
        shoppingItems: lastList?.items ?? const [],
      );

  Future<void> shareReport(GeneratedReportFile file) =>
      _reportDelivery.share(file);

  Future<void> printReport(GeneratedReportFile file) =>
      _reportDelivery.printPdf(file);

  List<ShoppingListModel> get activeLists {
    final result = lists.where((list) => !list.archived).toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  List<ShoppingListModel> get archivedLists {
    final result = lists.where((list) => list.archived).toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  ShoppingListModel? get lastList {
    if (lastListId == null) {
      return activeLists.isEmpty ? null : activeLists.first;
    }
    for (final list in lists) {
      if (list.id == lastListId && !list.archived) return list;
    }
    return activeLists.isEmpty ? null : activeLists.first;
  }

  Future<void> load() async {
    final data = await _repository.load();
    lists
      ..clear()
      ..addAll(data.lists);
    favorites
      ..clear()
      ..addAll(data.favorites);
    frequency
      ..clear()
      ..addAll(data.frequency);
    _inventory.replaceState(
      items: data.pantry,
      movements: data.pantryMovements,
    );
    lastListId = data.lastListId;
    themeMode = _themeModeFromName(data.themeMode);
    fontScale = data.fontScale.clamp(0.9, 1.25).toDouble();
    notificationSettings = data.notificationSettings;

    var needsSave = false;
    if (lists.isEmpty) {
      final now = DateTime.now();
      lists.add(
        ShoppingListModel(
          id: _newId(),
          name: 'مقاضي البيت',
          createdAt: now,
          updatedAt: now,
        ),
      );
      lastListId = lists.first.id;
      needsSave = true;
    }

    needsSave = _synchronizeAutomaticShoppingList() || needsSave;
    if (needsSave) await save();

    isReady = true;
    notifyListeners();
    unawaited(_synchronizeNotifications());
  }

  Future<void> save() => _repository.save(
        AppData(
          lists: lists,
          favorites: favorites,
          frequency: frequency,
          pantry: pantry,
          pantryMovements: pantryMovements,
          lastListId: lastListId,
          themeMode: themeMode.name,
          fontScale: fontScale,
          notificationSettings: notificationSettings,
        ),
      );

  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 220), save);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  ShoppingListModel createList(String name) {
    final now = DateTime.now();
    final list = ShoppingListModel(
      id: _newId(),
      name: name.trim().isEmpty ? 'قائمة جديدة' : name.trim(),
      createdAt: now,
      updatedAt: now,
    );
    lists.add(list);
    lastListId = list.id;
    _synchronizeAutomaticShoppingList();
    _changed();
    return list;
  }

  void openList(ShoppingListModel list) {
    lastListId = list.id;
    list.updatedAt = DateTime.now();
    _synchronizeAutomaticShoppingList();
    _changed();
  }

  void renameList(ShoppingListModel list, String name) {
    if (name.trim().isEmpty) return;
    list.name = name.trim();
    list.updatedAt = DateTime.now();
    _changed();
  }

  ShoppingListModel duplicateList(ShoppingListModel source) {
    final now = DateTime.now();
    final copy = ShoppingListModel(
      id: _newId(),
      name: '${source.name} - نسخة',
      createdAt: now,
      updatedAt: now,
      items: source.items
          .map(
            (item) => GroceryItem(
              id: '${_newId()}_${item.id}',
              name: item.name,
              category: item.category,
              quantity: item.quantity,
              pantryItemId: item.pantryItemId,
            ),
          )
          .toList(),
    );
    lists.add(copy);
    lastListId = copy.id;
    _synchronizeAutomaticShoppingList();
    _changed();
    return copy;
  }

  void archiveList(ShoppingListModel list, bool archived) {
    list.archived = archived;
    list.updatedAt = DateTime.now();
    if (lastListId == list.id) {
      lastListId = activeLists.isEmpty ? null : activeLists.first.id;
    }
    _synchronizeAutomaticShoppingList();
    _changed();
  }

  void deleteList(ShoppingListModel list) {
    lists.removeWhere((item) => item.id == list.id);
    if (lastListId == list.id) {
      lastListId = activeLists.isEmpty ? null : activeLists.first.id;
    }
    _synchronizeAutomaticShoppingList();
    _changed();
  }

  Product? exactProduct(String name) {
    final normalized = normalizeArabic(name);
    for (final product in products) {
      if (normalizeArabic(product.name) == normalized ||
          product.aliases.any(
            (alias) => normalizeArabic(alias) == normalized,
          )) {
        return product;
      }
    }
    return null;
  }

  String categoryFor(String name) {
    final exact = exactProduct(name);
    if (exact != null) return exact.category;
    final normalized = normalizeArabic(name);
    for (final product in products) {
      if (normalized.contains(normalizeArabic(product.name)) ||
          product.aliases.any(
            (alias) => normalized.contains(normalizeArabic(alias)),
          )) {
        return product.category;
      }
    }
    return 'أخرى';
  }

  void addItems(ShoppingListModel list, String raw, [String? category]) {
    var changed = false;
    for (final value in raw
        .split(RegExp(r'[\n,،]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)) {
      GroceryItem? existing;
      for (final item in list.items) {
        if (normalizeArabic(item.name) == normalizeArabic(value)) {
          existing = item;
          break;
        }
      }
      if (existing != null) {
        existing.quantity++;
      } else {
        final canonical = exactProduct(value)?.name ?? value;
        list.items.add(
          GroceryItem(
            id: _newId(),
            name: canonical,
            category: category ?? categoryFor(value),
          ),
        );
        frequency[canonical] = (frequency[canonical] ?? 0) + 1;
      }
      changed = true;
    }
    if (changed) {
      list.updatedAt = DateTime.now();
      _changed();
    }
  }

  void updateItem(ShoppingListModel list) {
    list.updatedAt = DateTime.now();
    _changed();
  }

  void removeItem(ShoppingListModel list, GroceryItem item) {
    list.items.remove(item);
    updateItem(list);
  }

  void restoreItem(ShoppingListModel list, GroceryItem item, int index) {
    final safeIndex = index.clamp(0, list.items.length);
    list.items.insert(safeIndex, item);
    updateItem(list);
  }

  void clearCompleted(ShoppingListModel list) {
    list.items.removeWhere((item) => item.done);
    _synchronizeAutomaticShoppingList();
    updateItem(list);
  }

  void markAllPending(ShoppingListModel list) {
    for (final item in list.items) {
      item.done = false;
    }
    updateItem(list);
  }

  void toggleFavorite(String name) {
    favorites.contains(name) ? favorites.remove(name) : favorites.add(name);
    _changed();
  }

  int get totalTrips => lists.where((list) => list.items.isNotEmpty).length;
  int get totalItems => lists.fold(0, (sum, list) => sum + list.items.length);
  int get completedItems =>
      lists.fold(0, (sum, list) => sum + list.completedCount);
  double get averageItemsPerTrip =>
      totalTrips == 0 ? 0 : totalItems / totalTrips;

  List<MapEntry<String, int>> get mostUsedProducts {
    final entries = frequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(20).toList();
  }

  List<PantryItem> get lowStockItems => _inventory.lowStockItems;
  List<PantryItem> get emptyPantryItems => _inventory.emptyItems;
  List<PantryItem> get healthyPantryItems => _inventory.healthyItems;

  StockInfo stockInfoFor(PantryItem item) => _inventory.stockInfoFor(item);

  List<StockInfo> stockItems(StockStatus status, {String query = ''}) =>
      _inventory.stockItems(status, query: query);

  List<PantryItem> pantryItems({
    String query = '',
    String? location,
    bool needsShoppingOnly = false,
  }) =>
      _inventory.pantryItems(
        query: query,
        location: location,
        needsShoppingOnly: needsShoppingOnly,
      );

  List<GroceryItem> shoppingItemsFor(
    ShoppingListModel list, {
    String query = '',
    StockStatus? stockStatus,
    bool hideDone = false,
  }) =>
      _inventory.shoppingItemsFor(
        list,
        query: query,
        stockStatus: stockStatus,
        hideDone: hideDone,
      );

  StockInfo? stockInfoForGrocery(GroceryItem grocery) =>
      _inventory.stockInfoForGrocery(grocery);

  int get shoppingListItemCount =>
      lastList?.items.where((item) => !item.done).length ?? 0;

  DashboardAnalytics dashboardAnalytics() =>
      _inventory.dashboardAnalytics(shoppingListItems: shoppingListItemCount);

  NotificationSummary get notificationSummary =>
      _inventory.notificationSummary(notificationSettings);

  List<SmartInventoryNotification> get pendingNotifications =>
      _inventory.pendingNotifications(notificationSettings);

  List<DashboardSearchResult> searchDashboard(String query) =>
      _inventory.searchDashboard(query);

  List<PantryMovement> movementsFor(PantryItem item) =>
      _inventory.movementsFor(item);

  List<InventoryBatch> batchesFor(PantryItem item) =>
      _inventory.batchesFor(item);

  BatchExpiryInfo expiryFor(PantryItem item, InventoryBatch batch) =>
      _inventory.expiryFor(item, batch);

  List<BatchExpiryInfo> expiryBatches(
    BatchExpiryStatus status, {
    String query = '',
  }) =>
      _inventory.expiryBatches(status, query: query);

  List<BatchExpiryInfo> expiringSoonBatches({String query = ''}) =>
      _inventory.expiringSoonBatches(query: query);

  List<BatchExpiryInfo> expiredBatches({String query = ''}) =>
      _inventory.expiredBatches(query: query);

  int putPurchasedItemsInPantry(ShoppingListModel list) {
    final purchased = list.items.where((item) => item.done).toList();
    if (purchased.isEmpty) return 0;
    for (final grocery in purchased) {
      _inventory.addStock(
        name: exactProduct(grocery.name)?.name ?? grocery.name,
        category: grocery.category,
        quantity: grocery.quantity.toDouble(),
        minimum: 1,
        unit: 'حبة',
        location: 'المخزن',
        movementType: 'شراء',
        note: _inventory.findByName(grocery.name) == null
            ? 'أضيف تلقائيًا من قائمة المقاضي'
            : 'من قائمة المقاضي',
        updateExistingDetails: false,
      );
    }
    list.items.removeWhere((item) => item.done);
    list.updatedAt = DateTime.now();
    _inventoryChanged();
    return purchased.length;
  }

  void addPantryItem({
    required String name,
    required double quantity,
    required double minimum,
    required String unit,
    required String location,
    String? primaryBarcode,
    Iterable<String> additionalBarcodes = const [],
  }) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    _inventory.validateBarcodes(
      primaryBarcode: primaryBarcode,
      additionalBarcodes: additionalBarcodes,
    );
    final item = _inventory.addStock(
      name: exactProduct(cleanName)?.name ?? cleanName,
      category: categoryFor(cleanName),
      quantity: quantity,
      minimum: minimum,
      unit: unit,
      location: location,
    );
    _inventory.setBarcodes(
      item,
      primaryBarcode: primaryBarcode,
      additionalBarcodes: additionalBarcodes,
    );
    _inventoryChanged();
  }

  void updatePantryItem(
    PantryItem item, {
    required String name,
    required double quantity,
    required double minimum,
    required String unit,
    required String location,
    String? primaryBarcode,
    Iterable<String>? additionalBarcodes,
  }) {
    final cleanName = name.trim().isEmpty ? item.name : name.trim();
    final shouldUpdateBarcodes =
        primaryBarcode != null || additionalBarcodes != null;
    if (shouldUpdateBarcodes) {
      _inventory.validateBarcodes(
        item: item,
        primaryBarcode: primaryBarcode,
        additionalBarcodes: additionalBarcodes ?? item.additionalBarcodes,
      );
    }
    _inventory.updateItem(
      item,
      name: cleanName,
      category: categoryFor(cleanName),
      quantity: quantity,
      minimum: minimum,
      unit: unit,
      location: location,
    );
    if (shouldUpdateBarcodes) {
      _inventory.setBarcodes(
        item,
        primaryBarcode: primaryBarcode,
        additionalBarcodes: additionalBarcodes ?? item.additionalBarcodes,
      );
    }
    _inventoryChanged();
  }

  InventoryScanResult resolveInventoryScan(String rawValue) =>
      _inventory.resolveScan(rawValue);

  bool addPantryBarcode(
    PantryItem item,
    String barcode, {
    bool makePrimary = false,
  }) {
    final changed = _inventory.addBarcode(
      item,
      barcode,
      makePrimary: makePrimary,
    );
    if (changed) _inventoryChanged();
    return changed;
  }

  bool makePrimaryPantryBarcode(PantryItem item, String barcode) {
    final changed = _inventory.makePrimaryBarcode(item, barcode);
    if (changed) _inventoryChanged();
    return changed;
  }

  bool removePantryBarcode(PantryItem item, String barcode) {
    final changed = _inventory.removeBarcode(item, barcode);
    if (changed) _inventoryChanged();
    return changed;
  }

  String productQrPayload(PantryItem item) => _inventory.productQrPayload(item);

  String batchQrPayload(PantryItem item, InventoryBatch batch) =>
      _inventory.batchQrPayload(item, batch);

  void changePantryQuantity(PantryItem item, double delta) {
    _inventory.changeQuantity(item, delta);
    _inventoryChanged();
  }

  InventoryBatch addPantryBatch(
    PantryItem item, {
    required double quantity,
    required DateTime purchasedAt,
    DateTime? expiresAt,
    String? batchId,
    String? note,
  }) {
    final batch = _inventory.addBatch(
      item,
      quantity: quantity,
      receivedAt: purchasedAt,
      expiresAt: expiresAt,
      batchId: batchId,
      note: note,
    );
    _inventoryChanged();
    return batch;
  }

  void updatePantryBatch(
    PantryItem item,
    InventoryBatch batch, {
    required double quantity,
    required DateTime purchasedAt,
    DateTime? expiresAt,
    String? batchId,
    String? note,
  }) {
    _inventory.updateBatch(
      item,
      batch,
      quantity: quantity,
      receivedAt: purchasedAt,
      expiresAt: expiresAt,
      batchId: batchId,
      note: note,
    );
    _inventoryChanged();
  }

  void deletePantryBatch(PantryItem item, InventoryBatch batch) {
    _inventory.deleteBatch(item, batch);
    _inventoryChanged();
  }

  void deletePantryItem(PantryItem item) {
    _inventory.deleteItem(item);
    _inventoryChanged();
  }

  void addLowStockToList(ShoppingListModel list) {
    final switchedList = lastListId != list.id;
    lastListId = list.id;
    if (_synchronizeAutomaticShoppingList() || switchedList) {
      _changed();
    }
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _changed();
  }

  void setFontScale(double value) {
    fontScale = value.clamp(0.9, 1.25).toDouble();
    _changed();
  }

  Future<bool> setNotificationSettings(NotificationSettings settings) async {
    notificationSettings = settings;
    _changed();
    final permissionGranted =
        settings.anyEnabled ? await requestNotificationPermissions() : true;
    await _synchronizeNotifications();
    return permissionGranted;
  }

  Future<bool> requestNotificationPermissions() async {
    try {
      return await _notificationScheduler.requestPermissions();
    } catch (_) {
      return false;
    }
  }

  void _changed() {
    notifyListeners();
    scheduleSave();
  }

  void _inventoryChanged() {
    _synchronizeAutomaticShoppingList();
    _changed();
    unawaited(_synchronizeNotifications());
  }

  Future<void> _persistPurchaseInventory() async {
    _synchronizeAutomaticShoppingList();
    await save();
    notifyListeners();
    unawaited(_synchronizeNotifications());
  }

  Future<void> _synchronizeNotifications() async {
    try {
      await _notificationScheduler.synchronize(
        _inventory.notificationSchedule(notificationSettings),
      );
    } catch (_) {
      // Inventory changes and saved data remain valid if a platform does not
      // support local scheduling or permission has not been granted yet.
    }
  }

  bool _synchronizeAutomaticShoppingList() {
    final target = lastList;
    var changed = false;
    for (final list in lists) {
      final listChanged = identical(list, target)
          ? _inventory.synchronizeAutomaticShoppingList(list, idFactory: _newId)
          : _inventory.removeAutomaticShoppingItems(list);
      if (listChanged) {
        list.updatedAt = DateTime.now();
        changed = true;
      }
    }
    return changed;
  }

  ThemeMode _themeModeFromName(String value) => switch (value) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };

  String _newId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }
}
