import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/price_history_models.dart';
import 'price_history_repository.dart';

typedef PriceHistoryPreferencesLoader = Future<SharedPreferences> Function();

class SharedPreferencesPriceHistoryRepository
    implements PriceHistoryRepository {
  SharedPreferencesPriceHistoryRepository({
    PriceHistoryPreferencesLoader? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const dataKey = 'maqadi_price_history_data_v53';
  static const schemaVersion = 1;

  final PriceHistoryPreferencesLoader _preferencesLoader;

  Future<void> migrate() async {
    final preferences = await _preferencesLoader();
    await _loadState(preferences);
  }

  @override
  Future<void> applyChanges({
    List<PriceHistoryRecord> added = const [],
    Set<String> removedPurchaseItemIds = const {},
  }) async {
    if (added.isEmpty && removedPurchaseItemIds.isEmpty) return;
    final preferences = await _preferencesLoader();
    final state = await _loadState(preferences);
    state.records.removeWhere(
      (record) => removedPurchaseItemIds.contains(record.purchaseItemId),
    );
    state.records.addAll(added);
    _validateUniqueRecords(state.records);
    await _saveState(preferences, state);
  }

  @override
  Future<void> replacePurchaseRecords(
    String purchaseId,
    List<PriceHistoryRecord> records,
  ) async {
    final preferences = await _preferencesLoader();
    final state = await _loadState(preferences);
    state.records.removeWhere((record) => record.purchaseId == purchaseId);
    state.records.addAll(records);
    _validateUniqueRecords(state.records);
    await _saveState(preferences, state);
  }

  @override
  Future<List<PriceHistoryRecord>> readByProduct(String productId) async {
    final state = await _loadState(await _preferencesLoader());
    return List.unmodifiable(
      state.records.where((record) => record.productId == productId),
    );
  }

  @override
  Future<List<PriceHistoryRecord>> readByPurchase(String purchaseId) async {
    final state = await _loadState(await _preferencesLoader());
    return List.unmodifiable(
      state.records.where((record) => record.purchaseId == purchaseId),
    );
  }

  Future<_PriceHistoryState> _loadState(
    SharedPreferences preferences,
  ) async {
    final raw = preferences.getString(dataKey);
    if (raw == null || raw.trim().isEmpty) return _PriceHistoryState();

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw FormatException('Invalid price history data: ${error.message}');
    }

    if (decoded is List) {
      final migrated = _PriceHistoryState(records: _decodeRecords(decoded));
      await _saveState(preferences, migrated);
      return migrated;
    }
    if (decoded is! Map) {
      throw const FormatException('Invalid price history data envelope.');
    }

    final map = Map<String, dynamic>.from(decoded);
    final version = (map['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version > schemaVersion) {
      throw StateError('Unsupported price history schema version $version.');
    }
    final state = _PriceHistoryState(
      records: _decodeRecords((map['records'] as List?) ?? const []),
    );
    if (version < schemaVersion) await _saveState(preferences, state);
    return state;
  }

  List<PriceHistoryRecord> _decodeRecords(List<dynamic> values) {
    final recordsByPurchaseItem = <String, PriceHistoryRecord>{};
    for (final value in values.whereType<Map>()) {
      final record = PriceHistoryRecord.fromJson(
        Map<String, dynamic>.from(value),
      );
      if (record.id.isEmpty || record.purchaseItemId.isEmpty) continue;
      recordsByPurchaseItem[record.purchaseItemId] = record;
    }
    return recordsByPurchaseItem.values.toList();
  }

  void _validateUniqueRecords(Iterable<PriceHistoryRecord> records) {
    final ids = <String>{};
    final purchaseItemIds = <String>{};
    for (final record in records) {
      if (record.id.trim().isEmpty || !ids.add(record.id)) {
        throw StateError('Price history record IDs must be unique.');
      }
      if (record.purchaseItemId.trim().isEmpty ||
          !purchaseItemIds.add(record.purchaseItemId)) {
        throw StateError(
          'Each purchase item can have only one price history record.',
        );
      }
    }
  }

  Future<void> _saveState(
    SharedPreferences preferences,
    _PriceHistoryState state,
  ) async {
    final saved = await preferences.setString(
      dataKey,
      jsonEncode({
        'schemaVersion': schemaVersion,
        'records': state.records.map((record) => record.toJson()).toList(),
      }),
    );
    if (!saved) throw StateError('Could not persist price history.');
  }
}

class _PriceHistoryState {
  _PriceHistoryState({List<PriceHistoryRecord>? records})
      : records = records ?? [];

  final List<PriceHistoryRecord> records;
}
