import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/purchase_models.dart';
import 'purchase_repository.dart';

typedef PurchasePreferencesLoader = Future<SharedPreferences> Function();

class SharedPreferencesPurchaseRepository implements PurchaseRepository {
  SharedPreferencesPurchaseRepository({
    PurchasePreferencesLoader? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const dataKey = 'maqadi_purchase_data_v51';
  static const schemaVersion = 1;

  final PurchasePreferencesLoader _preferencesLoader;

  Future<void> migrate() async {
    final prefs = await _preferencesLoader();
    await _loadState(prefs);
  }

  @override
  Future<Purchase> createPurchase(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    final prefs = await _preferencesLoader();
    final state = await _loadState(prefs);
    if (state.purchases.any((entry) => entry.id == purchase.id)) {
      throw StateError('Purchase ${purchase.id} already exists.');
    }
    state.purchases.add(purchase);
    state.items.addAll(_itemsForPurchase(purchase.id, items));
    await _saveState(prefs, state);
    return purchase;
  }

  @override
  Future<Purchase> updatePurchase(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    final prefs = await _preferencesLoader();
    final state = await _loadState(prefs);
    final index = state.purchases.indexWhere(
      (entry) => entry.id == purchase.id,
    );
    if (index < 0) {
      throw StateError('Purchase ${purchase.id} does not exist.');
    }
    state.purchases[index] = purchase;
    state.items.removeWhere((item) => item.purchaseId == purchase.id);
    state.items.addAll(_itemsForPurchase(purchase.id, items));
    await _saveState(prefs, state);
    return purchase;
  }

  @override
  Future<void> deletePurchase(String purchaseId) async {
    final prefs = await _preferencesLoader();
    final state = await _loadState(prefs);
    state.purchases.removeWhere((purchase) => purchase.id == purchaseId);
    state.items.removeWhere((item) => item.purchaseId == purchaseId);
    await _saveState(prefs, state);
  }

  @override
  Future<Purchase?> readPurchase(String purchaseId) async {
    final state = await _state();
    for (final purchase in state.purchases) {
      if (purchase.id == purchaseId) return purchase;
    }
    return null;
  }

  @override
  Future<List<Purchase>> readPurchaseHistory() async {
    final state = await _state();
    final result = List<Purchase>.from(state.purchases)
      ..sort(_compareNewestPurchase);
    return List.unmodifiable(result);
  }

  @override
  Future<List<Purchase>> readPurchasesByDate(DateTime date) async {
    final history = await readPurchaseHistory();
    return List.unmodifiable(
      history.where((purchase) => _sameDate(purchase.purchaseDate, date)),
    );
  }

  @override
  Future<List<Purchase>> readPurchasesByStore(String storeId) async {
    final history = await readPurchaseHistory();
    return List.unmodifiable(
      history.where((purchase) => purchase.storeId == storeId),
    );
  }

  @override
  Future<List<PurchaseItem>> readPurchaseDetails(String purchaseId) async {
    final state = await _state();
    final result = state.items
        .where((item) => item.purchaseId == purchaseId)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(result);
  }

  Future<_PurchaseState> _state() async {
    final prefs = await _preferencesLoader();
    return _loadState(prefs);
  }

  Future<_PurchaseState> _loadState(SharedPreferences prefs) async {
    final migrated = _decodeState(prefs.getString(dataKey));
    if (migrated.needsWrite) await _saveState(prefs, migrated.state);
    return migrated.state;
  }

  _MigratedPurchaseState _decodeState(String? raw) {
    if (raw == null) {
      return _MigratedPurchaseState(_PurchaseState(), needsWrite: true);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return _MigratedPurchaseState(
          _legacyListState(decoded),
          needsWrite: true,
        );
      }
      if (decoded is! Map) {
        return _MigratedPurchaseState(_PurchaseState(), needsWrite: true);
      }
      final map = Map<String, dynamic>.from(decoded);
      final state = _stateFromMap(map);
      return _MigratedPurchaseState(
        state,
        needsWrite: (map['schemaVersion'] as num?)?.toInt() != schemaVersion ||
            _hasNestedItems(map['purchases']),
      );
    } catch (_) {
      return _MigratedPurchaseState(_PurchaseState(), needsWrite: false);
    }
  }

  _PurchaseState _legacyListState(List<dynamic> purchases) =>
      _stateFromMap({'purchases': purchases, 'items': const <dynamic>[]});

  _PurchaseState _stateFromMap(Map<String, dynamic> map) {
    final purchases = <Purchase>[];
    final items = <PurchaseItem>[];
    for (final rawPurchase in (map['purchases'] as List?) ?? const []) {
      if (rawPurchase is! Map) continue;
      final purchaseMap = Map<String, dynamic>.from(rawPurchase);
      final purchase = Purchase.fromJson(purchaseMap);
      if (purchase.id.isEmpty) continue;
      purchases.add(purchase);
      for (final rawItem in (purchaseMap['items'] as List?) ?? const []) {
        if (rawItem is! Map) continue;
        items.add(
          PurchaseItem.fromJson({
            ...Map<String, dynamic>.from(rawItem),
            'purchaseId': purchase.id,
          }),
        );
      }
    }
    for (final rawItem in (map['items'] as List?) ?? const []) {
      if (rawItem is! Map) continue;
      final item = PurchaseItem.fromJson(Map<String, dynamic>.from(rawItem));
      if (item.id.isNotEmpty && item.purchaseId.isNotEmpty) items.add(item);
    }
    final purchasesById = <String, Purchase>{
      for (final purchase in purchases) purchase.id: purchase,
    };
    final itemsById = <String, PurchaseItem>{
      for (final item in items) '${item.purchaseId}|${item.id}': item,
    };
    return _PurchaseState(
      purchases: purchasesById.values.toList(),
      items: itemsById.values.toList(),
    );
  }

  Future<void> _saveState(SharedPreferences prefs, _PurchaseState state) async {
    await prefs.setString(
      dataKey,
      jsonEncode({
        'schemaVersion': schemaVersion,
        'purchases':
            state.purchases.map((purchase) => purchase.toJson()).toList(),
        'items': state.items.map((item) => item.toJson()).toList(),
      }),
    );
  }

  List<PurchaseItem> _itemsForPurchase(
    String purchaseId,
    Iterable<PurchaseItem> items,
  ) =>
      items.map((item) => item.copyWith(purchaseId: purchaseId)).toList();

  bool _hasNestedItems(Object? purchases) =>
      purchases is List &&
      purchases.any((purchase) => purchase is Map && purchase['items'] is List);

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _compareNewestPurchase(Purchase a, Purchase b) {
    final byDate = b.purchaseDate.compareTo(a.purchaseDate);
    return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
  }
}

class _PurchaseState {
  _PurchaseState({List<Purchase>? purchases, List<PurchaseItem>? items})
      : purchases = purchases ?? [],
        items = items ?? [];

  final List<Purchase> purchases;
  final List<PurchaseItem> items;
}

class _MigratedPurchaseState {
  const _MigratedPurchaseState(this.state, {required this.needsWrite});

  final _PurchaseState state;
  final bool needsWrite;
}
