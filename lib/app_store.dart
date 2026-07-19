import 'dart:async';

import 'package:flutter/material.dart';

import 'models/expiry_models.dart';
import 'models/inventory_models.dart';
import 'models/shopping_models.dart';
import 'models/stock_models.dart';
import 'products.dart';
import 'repositories/app_repository.dart';
import 'repositories/shared_preferences_app_repository.dart';
import 'services/inventory_service.dart';
import 'utils/arabic_text.dart';

class AppStore extends ChangeNotifier {
  AppStore({AppRepository? repository, InventoryService? inventoryService})
      : _repository = repository ?? SharedPreferencesAppRepository(),
        _inventory = inventoryService ?? InventoryService();

  final AppRepository _repository;
  final InventoryService _inventory;
  final List<ShoppingListModel> lists = [];
  final Set<String> favorites = {};
  final Map<String, int> frequency = {};
  String? lastListId;
  ThemeMode themeMode = ThemeMode.system;
  double fontScale = 1;
  bool isReady = false;
  Timer? _saveTimer;
  int _idCounter = 0;

  List<PantryItem> get pantry => _inventory.items;
  List<PantryMovement> get pantryMovements => _inventory.movements;

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
  }) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    _inventory.addStock(
      name: exactProduct(cleanName)?.name ?? cleanName,
      category: categoryFor(cleanName),
      quantity: quantity,
      minimum: minimum,
      unit: unit,
      location: location,
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
  }) {
    final cleanName = name.trim().isEmpty ? item.name : name.trim();
    _inventory.updateItem(
      item,
      name: cleanName,
      category: categoryFor(cleanName),
      quantity: quantity,
      minimum: minimum,
      unit: unit,
      location: location,
    );
    _inventoryChanged();
  }

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

  void _changed() {
    notifyListeners();
    scheduleSave();
  }

  void _inventoryChanged() {
    _synchronizeAutomaticShoppingList();
    _changed();
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
