import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/purchase_models.dart';
import 'store_repository.dart';

typedef StorePreferencesLoader = Future<SharedPreferences> Function();

class SharedPreferencesStoreRepository implements StoreRepository {
  SharedPreferencesStoreRepository({StorePreferencesLoader? preferencesLoader})
      : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const dataKey = 'maqadi_store_data_v54';
  static const schemaVersion = 1;

  final StorePreferencesLoader _preferencesLoader;

  Future<void> migrate() async {
    final prefs = await _preferencesLoader();
    await _loadStores(prefs);
  }

  @override
  Future<Store> createStore(Store store) async {
    final prefs = await _preferencesLoader();
    final stores = await _loadStores(prefs);
    if (stores.any((entry) => entry.id == store.id)) {
      throw StateError('Store ${store.id} already exists.');
    }
    stores.add(store);
    await _saveStores(prefs, stores);
    return store;
  }

  @override
  Future<Store> updateStore(Store store) async {
    final prefs = await _preferencesLoader();
    final stores = await _loadStores(prefs);
    final index = stores.indexWhere((entry) => entry.id == store.id);
    if (index < 0) throw StateError('Store ${store.id} does not exist.');
    stores[index] = store;
    await _saveStores(prefs, stores);
    return store;
  }

  @override
  Future<void> deleteStore(String storeId) async {
    final prefs = await _preferencesLoader();
    final stores = await _loadStores(prefs);
    stores.removeWhere((store) => store.id == storeId);
    await _saveStores(prefs, stores);
  }

  @override
  Future<Store?> readStore(String storeId) async {
    final stores = await readStores();
    for (final store in stores) {
      if (store.id == storeId) return store;
    }
    return null;
  }

  @override
  Future<List<Store>> readStores() async {
    final prefs = await _preferencesLoader();
    final stores = await _loadStores(prefs)
      ..sort(_compareStores);
    return List.unmodifiable(stores);
  }

  @override
  Future<List<Store>> readActiveStores() async => List.unmodifiable(
        (await readStores()).where((store) => store.isActive),
      );

  @override
  Future<List<Store>> readArchivedStores() async => List.unmodifiable(
        (await readStores()).where((store) => !store.isActive),
      );

  Future<List<Store>> _loadStores(SharedPreferences prefs) async {
    final decoded = _decode(prefs.getString(dataKey));
    if (decoded.needsWrite) await _saveStores(prefs, decoded.stores);
    return decoded.stores;
  }

  _DecodedStores _decode(String? raw) {
    if (raw == null) return _DecodedStores(<Store>[], needsWrite: true);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return _DecodedStores(_storesFrom(decoded), needsWrite: true);
      }
      if (decoded is! Map) {
        return _DecodedStores(<Store>[], needsWrite: true);
      }
      final map = Map<String, dynamic>.from(decoded);
      return _DecodedStores(
        _storesFrom((map['stores'] as List?) ?? const []),
        needsWrite: (map['schemaVersion'] as num?)?.toInt() != schemaVersion,
      );
    } catch (_) {
      return _DecodedStores(<Store>[], needsWrite: false);
    }
  }

  List<Store> _storesFrom(List<dynamic> values) {
    final byId = <String, Store>{};
    for (final value in values) {
      if (value is! Map) continue;
      final store = Store.fromJson(Map<String, dynamic>.from(value));
      if (store.id.isNotEmpty) byId[store.id] = store;
    }
    return byId.values.toList();
  }

  Future<void> _saveStores(
    SharedPreferences prefs,
    Iterable<Store> stores,
  ) =>
      prefs.setString(
        dataKey,
        jsonEncode({
          'schemaVersion': schemaVersion,
          'stores': stores.map((store) => store.toJson()).toList(),
        }),
      );

  int _compareStores(Store a, Store b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.createdAt.compareTo(b.createdAt);
  }
}

class _DecodedStores {
  const _DecodedStores(this.stores, {required this.needsWrite});

  final List<Store> stores;
  final bool needsWrite;
}
