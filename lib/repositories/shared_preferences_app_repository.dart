import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/inventory_models.dart';
import '../models/notification_models.dart';
import '../models/shopping_models.dart';
import 'app_repository.dart';

typedef PreferencesLoader = Future<SharedPreferences> Function();

class SharedPreferencesAppRepository implements AppRepository {
  SharedPreferencesAppRepository({PreferencesLoader? preferencesLoader})
      : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const listsKey = 'maqadi_lists_v25';
  static const favoritesKey = 'maqadi_favorites_v25';
  static const frequencyKey = 'maqadi_frequency_v25';
  static const lastListKey = 'maqadi_last_list_v25';
  static const themeKey = 'maqadi_theme_v25';
  static const fontScaleKey = 'maqadi_font_scale_v25';
  static const pantryKey = 'maqadi_pantry_v26';
  static const movementsKey = 'maqadi_pantry_movements_v26_p2';
  static const notificationSettingsKey = 'maqadi_notification_settings_v45';
  static const schemaVersionKey = 'maqadi_schema_version';
  static const schemaVersion = 31;

  final PreferencesLoader _preferencesLoader;

  @override
  Future<AppData> load() async {
    final prefs = await _preferencesLoader();

    return AppData(
      lists: _decodeList(prefs.getString(listsKey), ShoppingListModel.fromJson),
      favorites: (prefs.getStringList(favoritesKey) ?? const []).toSet(),
      frequency: _decodeFrequency(prefs.getString(frequencyKey)),
      pantry: _decodeList(prefs.getString(pantryKey), PantryItem.fromJson),
      pantryMovements: _decodeList(
        prefs.getString(movementsKey),
        PantryMovement.fromJson,
      ),
      lastListId: prefs.getString(lastListKey),
      themeMode: prefs.getString(themeKey) ?? 'system',
      fontScale:
          (prefs.getDouble(fontScaleKey) ?? 1).clamp(0.9, 1.25).toDouble(),
      notificationSettings: _decodeNotificationSettings(
        prefs.getString(notificationSettingsKey),
      ),
    );
  }

  @override
  Future<void> save(AppData data) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(
      listsKey,
      jsonEncode(data.lists.map((list) => list.toJson()).toList()),
    );
    await prefs.setStringList(favoritesKey, data.favorites.toList());
    await prefs.setString(frequencyKey, jsonEncode(data.frequency));
    if (data.lastListId == null) {
      await prefs.remove(lastListKey);
    } else {
      await prefs.setString(lastListKey, data.lastListId!);
    }
    await prefs.setString(themeKey, data.themeMode);
    await prefs.setDouble(fontScaleKey, data.fontScale);
    await prefs.setString(
      pantryKey,
      jsonEncode(data.pantry.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(
      movementsKey,
      jsonEncode(
        data.pantryMovements.map((movement) => movement.toJson()).toList(),
      ),
    );
    await prefs.setString(
      notificationSettingsKey,
      jsonEncode(data.notificationSettings.toJson()),
    );
    await prefs.setInt(schemaVersionKey, schemaVersion);
  }

  List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, int> _decodeFrequency(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return Map<String, dynamic>.from(
        decoded,
      ).map((key, value) => MapEntry(key, value is num ? value.toInt() : 0));
    } catch (_) {
      return {};
    }
  }

  NotificationSettings _decodeNotificationSettings(String? raw) {
    if (raw == null) return const NotificationSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const NotificationSettings();
      return NotificationSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const NotificationSettings();
    }
  }
}
