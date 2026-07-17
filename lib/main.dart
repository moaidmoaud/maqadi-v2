import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'products.dart';

void main() => runApp(const MaqadiApp());

String normalizeArabic(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ؤ', 'و')
    .replaceAll('ئ', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'[^\u0621-\u064A0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> searchTokens(String value) =>
    normalizeArabic(value).split(' ').where((token) => token.isNotEmpty).toList();

class GroceryItem {
  GroceryItem({
    required this.id,
    required this.name,
    required this.category,
    this.done = false,
    this.quantity = 1,
  });

  final String id;
  String name;
  String category;
  bool done;
  int quantity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'done': done,
        'quantity': quantity,
      };

  factory GroceryItem.fromJson(Map<String, dynamic> json) => GroceryItem(
        id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'أخرى',
        done: json['done'] as bool? ?? false,
        quantity: json['quantity'] as int? ?? json['qty'] as int? ?? 1,
      );
}


class PantryItem {
  PantryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.quantity,
    required this.minimum,
    required this.unit,
    required this.location,
  });

  final String id;
  String name;
  String category;
  double quantity;
  double minimum;
  String unit;
  String location;

  bool get isLow => quantity <= minimum;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'quantity': quantity,
        'minimum': minimum,
        'unit': unit,
        'location': location,
      };

  factory PantryItem.fromJson(Map<String, dynamic> json) => PantryItem(
        id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? 'أخرى',
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        minimum: (json['minimum'] as num?)?.toDouble() ?? 1,
        unit: json['unit'] as String? ?? 'حبة',
        location: json['location'] as String? ?? 'المخزن',
      );
}

class ShoppingListModel {
  ShoppingListModel({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    List<GroceryItem>? items,
    this.archived = false,
  }) : items = items ?? [];

  final String id;
  String name;
  DateTime createdAt;
  DateTime updatedAt;
  List<GroceryItem> items;
  bool archived;

  int get completedCount => items.where((item) => item.done).length;
  int get remainingCount => items.length - completedCount;
  double get progress => items.isEmpty ? 0 : completedCount / items.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(),
        'archived': archived,
      };

  factory ShoppingListModel.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return ShoppingListModel(
      id: json['id'] as String? ?? now.microsecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'قائمة جديدة',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      items: ((json['items'] as List?) ?? const [])
          .map((item) => GroceryItem.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      archived: json['archived'] as bool? ?? false,
    );
  }
}

class AppStore extends ChangeNotifier {
  static const _listsKey = 'maqadi_lists_v25';
  static const _favoritesKey = 'maqadi_favorites_v25';
  static const _frequencyKey = 'maqadi_frequency_v25';
  static const _lastListKey = 'maqadi_last_list_v25';
  static const _themeKey = 'maqadi_theme_v25';
  static const _fontScaleKey = 'maqadi_font_scale_v25';
  static const _pantryKey = 'maqadi_pantry_v26';

  final List<ShoppingListModel> lists = [];
  final Set<String> favorites = {};
  final Map<String, int> frequency = {};
  final List<PantryItem> pantry = [];
  String? lastListId;
  ThemeMode themeMode = ThemeMode.system;
  double fontScale = 1.0;
  bool isReady = false;
  Timer? _saveTimer;
  int _idCounter = 0;

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
    if (lastListId == null) return activeLists.isEmpty ? null : activeLists.first;
    for (final list in lists) {
      if (list.id == lastListId && !list.archived) return list;
    }
    return activeLists.isEmpty ? null : activeLists.first;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawLists = prefs.getString(_listsKey);
    final rawFrequency = prefs.getString(_frequencyKey);
    final rawPantry = prefs.getString(_pantryKey);

    try {
      if (rawLists != null) {
        final decoded = jsonDecode(rawLists);
        if (decoded is List) {
          lists.addAll(decoded.whereType<Map>().map(
                (item) => ShoppingListModel.fromJson(Map<String, dynamic>.from(item)),
              ));
        }
      }
    } catch (_) {
      // نبدأ بقائمة سليمة بدل تعطّل التطبيق إذا تلفت البيانات المحلية.
    }
    favorites.addAll(prefs.getStringList(_favoritesKey) ?? const []);
    try {
      if (rawFrequency != null) {
        final decoded = jsonDecode(rawFrequency);
        if (decoded is Map) {
          frequency.addAll(Map<String, dynamic>.from(decoded).map(
            (key, value) => MapEntry(key, value is int ? value : 0),
          ));
        }
      }
    } catch (_) {
      frequency.clear();
    }
    try {
      if (rawPantry != null) {
        final decoded = jsonDecode(rawPantry);
        if (decoded is List) {
          pantry.addAll(decoded.whereType<Map>().map(
                (item) => PantryItem.fromJson(Map<String, dynamic>.from(item)),
              ));
        }
      }
    } catch (_) {
      pantry.clear();
    }
    lastListId = prefs.getString(_lastListKey);
    final savedTheme = prefs.getString(_themeKey);
    themeMode = savedTheme == 'dark'
        ? ThemeMode.dark
        : savedTheme == 'light'
            ? ThemeMode.light
            : ThemeMode.system;
    fontScale = (prefs.getDouble(_fontScaleKey) ?? 1.0).clamp(0.9, 1.25).toDouble();

    if (lists.isEmpty) {
      lists.add(ShoppingListModel(
        id: _newId(),
        name: 'مقاضي البيت',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      lastListId = lists.first.id;
      await save();
    }

    isReady = true;
    notifyListeners();
  }

  String _newId() {
    _idCounter++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_listsKey, jsonEncode(lists.map((list) => list.toJson()).toList()));
    await prefs.setStringList(_favoritesKey, favorites.toList());
    await prefs.setString(_frequencyKey, jsonEncode(frequency));
    if (lastListId != null) {
      await prefs.setString(_lastListKey, lastListId!);
    } else {
      await prefs.remove(_lastListKey);
    }
    await prefs.setString(_themeKey, themeMode.name);
    await prefs.setDouble(_fontScaleKey, fontScale);
    await prefs.setString(_pantryKey, jsonEncode(pantry.map((item) => item.toJson()).toList()));
  }

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
    notifyListeners();
    scheduleSave();
    return list;
  }

  void openList(ShoppingListModel list) {
    lastListId = list.id;
    list.updatedAt = DateTime.now();
    notifyListeners();
    scheduleSave();
  }

  void renameList(ShoppingListModel list, String name) {
    if (name.trim().isEmpty) return;
    list.name = name.trim();
    list.updatedAt = DateTime.now();
    notifyListeners();
    scheduleSave();
  }

  ShoppingListModel duplicateList(ShoppingListModel source) {
    final now = DateTime.now();
    final copy = ShoppingListModel(
      id: _newId(),
      name: '${source.name} - نسخة',
      createdAt: now,
      updatedAt: now,
      items: source.items
          .map((item) => GroceryItem(
                id: '${_newId()}_${item.id}',
                name: item.name,
                category: item.category,
                quantity: item.quantity,
              ))
          .toList(),
    );
    lists.add(copy);
    lastListId = copy.id;
    notifyListeners();
    scheduleSave();
    return copy;
  }

  void archiveList(ShoppingListModel list, bool archived) {
    list.archived = archived;
    list.updatedAt = DateTime.now();
    if (lastListId == list.id) lastListId = activeLists.isEmpty ? null : activeLists.first.id;
    notifyListeners();
    scheduleSave();
  }

  void deleteList(ShoppingListModel list) {
    lists.removeWhere((item) => item.id == list.id);
    if (lastListId == list.id) lastListId = activeLists.isEmpty ? null : activeLists.first.id;
    notifyListeners();
    scheduleSave();
  }

  Product? exactProduct(String name) {
    final normalized = normalizeArabic(name);
    for (final product in products) {
      if (normalizeArabic(product.name) == normalized ||
          product.aliases.any((alias) => normalizeArabic(alias) == normalized)) {
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
          product.aliases.any((alias) => normalized.contains(normalizeArabic(alias)))) {
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
        list.items.add(GroceryItem(
          id: _newId(),
          name: canonical,
          category: category ?? categoryFor(value),
        ));
        frequency[canonical] = (frequency[canonical] ?? 0) + 1;
      }
      changed = true;
    }
    if (changed) {
      list.updatedAt = DateTime.now();
      notifyListeners();
      scheduleSave();
    }
  }

  void updateItem(ShoppingListModel list) {
    list.updatedAt = DateTime.now();
    notifyListeners();
    scheduleSave();
  }

  void removeItem(ShoppingListModel list, GroceryItem item) {
    list.items.remove(item);
    updateItem(list);
  }

  void restoreItem(ShoppingListModel list, GroceryItem item, int index) {
    final safeIndex = index.clamp(0, list.items.length) as int;
    list.items.insert(safeIndex, item);
    updateItem(list);
  }

  void clearCompleted(ShoppingListModel list) {
    list.items.removeWhere((item) => item.done);
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
    notifyListeners();
    scheduleSave();
  }

  int get totalTrips => lists.where((list) => list.items.isNotEmpty).length;
  int get totalItems => lists.fold(0, (sum, list) => sum + list.items.length);
  int get completedItems => lists.fold(0, (sum, list) => sum + list.completedCount);
  double get averageItemsPerTrip => totalTrips == 0 ? 0 : totalItems / totalTrips;

  List<MapEntry<String, int>> get mostUsedProducts {
    final entries = frequency.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(20).toList();
  }


  List<PantryItem> get lowStockItems {
    final result = pantry.where((item) => item.isLow).toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
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
    final existing = pantry.where((item) => normalizeArabic(item.name) == normalizeArabic(cleanName)).toList();
    if (existing.isNotEmpty) {
      existing.first.quantity += quantity;
      existing.first.minimum = minimum;
      existing.first.unit = unit;
      existing.first.location = location;
    } else {
      pantry.add(PantryItem(
        id: _newId(),
        name: exactProduct(cleanName)?.name ?? cleanName,
        category: categoryFor(cleanName),
        quantity: quantity,
        minimum: minimum,
        unit: unit,
        location: location,
      ));
    }
    notifyListeners();
    scheduleSave();
  }

  void updatePantryItem(PantryItem item) {
    notifyListeners();
    scheduleSave();
  }

  void changePantryQuantity(PantryItem item, double delta) {
    item.quantity = (item.quantity + delta).clamp(0, 999999).toDouble();
    updatePantryItem(item);
  }

  void deletePantryItem(PantryItem item) {
    pantry.remove(item);
    notifyListeners();
    scheduleSave();
  }

  void addLowStockToList(ShoppingListModel list) {
    for (final item in lowStockItems) {
      final needed = (item.minimum - item.quantity).ceil().clamp(1, 999);
      final existing = list.items.where((g) => normalizeArabic(g.name) == normalizeArabic(item.name)).toList();
      if (existing.isEmpty) {
        list.items.add(GroceryItem(
          id: _newId(),
          name: item.name,
          category: item.category,
          quantity: needed,
        ));
      }
    }
    list.updatedAt = DateTime.now();
    notifyListeners();
    scheduleSave();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
    scheduleSave();
  }

  void setFontScale(double value) {
    fontScale = value.clamp(0.9, 1.25).toDouble();
    notifyListeners();
    scheduleSave();
  }
}


class MaqadiApp extends StatefulWidget {
  const MaqadiApp({super.key});

  @override
  State<MaqadiApp> createState() => _MaqadiAppState();
}

class _MaqadiAppState extends State<MaqadiApp> {
  final AppStore store = AppStore();

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'مقاضي',
          themeMode: store.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF2E7D32),
            scaffoldBackgroundColor: const Color(0xFFF7F8F6),
            cardTheme: const CardThemeData(margin: EdgeInsets.zero),
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF66BB6A),
              brightness: Brightness.dark,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(store.fontScale)),
            child: child!,
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: store.isReady
                ? HomeScreen(
                    store: store,
                    onToggleTheme: () => store.setThemeMode(
                      store.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
                    ),
                  )
                : const Scaffold(body: Center(child: CircularProgressIndicator())),
          ),
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.onToggleTheme});

  final AppStore store;
  final VoidCallback onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool showArchived = false;

  Future<String?> _askName(BuildContext context, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial.isEmpty ? 'قائمة جديدة' : 'إعادة تسمية القائمة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'مثال: مقاضي البيت'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('حفظ')),
        ],
      ),
    );
  }

  Future<void> _createList() async {
    final name = await _askName(context);
    if (!mounted || name == null) return;
    final list = widget.store.createList(name);
    _openList(list);
  }

  void _openList(ShoppingListModel list) {
    widget.store.openList(list);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: ShoppingScreen(store: widget.store, list: list),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(ShoppingListModel list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف القائمة؟'),
        content: Text('سيتم حذف "${list.name}" نهائيًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) widget.store.deleteList(list);
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.store.lastList;
    final visibleLists = showArchived ? widget.store.archivedLists : widget.store.activeLists;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مقاضي', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: SettingsScreen(store: widget.store)))),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(onPressed: widget.onToggleTheme, icon: const Icon(Icons.dark_mode_outlined)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createList,
        icon: const Icon(Icons.add),
        label: const Text('قائمة جديدة'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          if (last != null)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openList(last),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.shopping_cart_checkout, size: 30),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('آخر قائمة', style: TextStyle(fontSize: 13)),
                                Text(last.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: last.progress, minHeight: 10, borderRadius: BorderRadius.circular(20)),
                      const SizedBox(height: 8),
                      Text('تم ${last.completedCount} من ${last.items.length} • المتبقي ${last.remainingCount}'),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => _openList(last),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('بدء التسوق'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _QuickCard(
                  icon: Icons.star_outline,
                  title: 'المفضلة',
                  subtitle: '${widget.store.favorites.length} منتج',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: FavoritesScreen(store: widget.store)))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickCard(
                  icon: Icons.bar_chart_outlined,
                  title: 'الإحصائيات',
                  subtitle: '${widget.store.lists.length} قائمة',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: StatisticsScreen(store: widget.store)))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _QuickCard(
            icon: Icons.inventory_2_outlined,
            title: 'مخزن المنزل',
            subtitle: '${widget.store.pantry.length} منتج • ${widget.store.lowStockItems.length} منخفض',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: PantryScreen(store: widget.store),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(showArchived ? 'القوائم المؤرشفة' : 'قوائمي', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              TextButton.icon(
                onPressed: () => setState(() => showArchived = !showArchived),
                icon: Icon(showArchived ? Icons.list_alt : Icons.archive_outlined),
                label: Text(showArchived ? 'عرض النشطة' : 'المؤرشفة'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visibleLists.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 52),
                    SizedBox(height: 8),
                    Text('لا توجد قوائم هنا'),
                  ],
                ),
              ),
            ),
          ...visibleLists.map(
            (list) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: () => _openList(list),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(child: Text('${list.remainingCount}')),
                  title: Text(list.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(value: list.progress, minHeight: 6, borderRadius: BorderRadius.circular(20)),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'rename') {
                        final name = await _askName(context, initial: list.name);
                        if (name != null) widget.store.renameList(list, name);
                      } else if (value == 'copy') {
                        final copy = widget.store.duplicateList(list);
                        _openList(copy);
                      } else if (value == 'archive') {
                        widget.store.archiveList(list, !list.archived);
                      } else if (value == 'delete') {
                        _confirmDelete(list);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                      if (!list.archived) const PopupMenuItem(value: 'copy', child: Text('نسخ القائمة')),
                      PopupMenuItem(value: 'archive', child: Text(list.archived ? 'إلغاء الأرشفة' : 'أرشفة')),
                      const PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
      );
}



class PantryScreen extends StatefulWidget {
  const PantryScreen({super.key, required this.store});
  final AppStore store;

  @override
  State<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends State<PantryScreen> {
  String query = '';
  String location = 'الكل';
  bool lowOnly = false;

  Future<void> _showEditor([PantryItem? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final quantity = TextEditingController(text: item == null ? '1' : _format(item.quantity));
    final minimum = TextEditingController(text: item == null ? '1' : _format(item.minimum));
    String unit = item?.unit ?? 'حبة';
    String place = item?.location ?? 'المخزن';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item == null ? 'إضافة للمخزن' : 'تعديل المنتج', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                TextField(controller: name, autofocus: item == null, decoration: const InputDecoration(labelText: 'اسم المنتج', prefixIcon: Icon(Icons.search))),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية الحالية'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الحد الأدنى'))),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'الوحدة'),
                  items: const ['حبة', 'عبوة', 'كرتون', 'كجم', 'جرام', 'لتر', 'مل', 'كيس', 'علبة'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setSheetState(() => unit = v ?? unit),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: place,
                  decoration: const InputDecoration(labelText: 'مكان التخزين'),
                  items: const ['المخزن', 'الثلاجة', 'الفريزر', 'التنظيف', 'الأطفال'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setSheetState(() => place = v ?? place),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != true) return;
    final q = double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0;
    final m = double.tryParse(minimum.text.replaceAll(',', '.')) ?? 0;
    if (item == null) {
      widget.store.addPantryItem(name: name.text, quantity: q, minimum: m, unit: unit, location: place);
    } else {
      item.name = name.text.trim().isEmpty ? item.name : name.text.trim();
      item.category = widget.store.categoryFor(item.name);
      item.quantity = q.clamp(0, 999999).toDouble();
      item.minimum = m.clamp(0, 999999).toDouble();
      item.unit = unit;
      item.location = place;
      widget.store.updatePantryItem(item);
    }
  }

  String _format(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(1);

  Future<void> _addLowToList() async {
    if (widget.store.lowStockItems.isEmpty) return;
    final active = widget.store.activeLists;
    ShoppingListModel? selected = widget.store.lastList;
    final result = await showDialog<ShoppingListModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة الناقص إلى قائمة'),
        content: active.isEmpty
            ? const Text('لا توجد قائمة نشطة. أنشئ قائمة أولاً من الصفحة الرئيسية.')
            : SizedBox(
                width: double.maxFinite,
                child: ListView(shrinkWrap: true, children: active.map((list) => RadioListTile<ShoppingListModel>(value: list, groupValue: selected, title: Text(list.name), onChanged: (v) => Navigator.pop(context, v))).toList()),
              ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء'))],
      ),
    );
    if (result != null) {
      widget.store.addLowStockToList(result);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تمت إضافة المنتجات الناقصة إلى ${result.name}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final allLocations = ['الكل', ...{for (final item in widget.store.pantry) item.location}];
    final items = widget.store.pantry.where((item) {
      final matchesQuery = normalizeArabic(item.name).contains(normalizeArabic(query));
      final matchesLocation = location == 'الكل' || item.location == location;
      return matchesQuery && matchesLocation && (!lowOnly || item.isLow);
    }).toList()
      ..sort((a, b) {
        if (a.isLow != b.isLow) return a.isLow ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('مخزن المنزل', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'إضافة الناقص للقائمة', onPressed: widget.store.lowStockItems.isEmpty ? null : _addLowToList, icon: const Icon(Icons.playlist_add)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showEditor(), icon: const Icon(Icons.add), label: const Text('إضافة منتج')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(children: [
              Row(children: [
                Expanded(child: _PantrySummary(icon: Icons.inventory_2_outlined, label: 'المنتجات', value: '${widget.store.pantry.length}')),
                const SizedBox(width: 10),
                Expanded(child: _PantrySummary(icon: Icons.warning_amber_rounded, label: 'منخفض', value: '${widget.store.lowStockItems.length}')),
              ]),
              const SizedBox(height: 12),
              TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(hintText: 'ابحث في المخزن', prefixIcon: Icon(Icons.search), border: OutlineInputBorder())),
              const SizedBox(height: 10),
              SizedBox(height: 40, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: allLocations.length + 1, separatorBuilder: (_, __) => const SizedBox(width: 8), itemBuilder: (_, index) {
                if (index == 0) return FilterChip(selected: lowOnly, label: const Text('الناقص فقط'), avatar: const Icon(Icons.warning_amber_rounded, size: 18), onSelected: (v) => setState(() => lowOnly = v));
                final value = allLocations[index - 1];
                return ChoiceChip(selected: location == value, label: Text(value), onSelected: (_) => setState(() => location = value));
              })),
            ]),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.inventory_2_outlined, size: 68), SizedBox(height: 12), Text('لا توجد منتجات مطابقة'), SizedBox(height: 4), Text('أضف أول منتج إلى مخزن المنزل')]))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _showEditor(item),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(children: [
                              CircleAvatar(backgroundColor: item.isLow ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.primaryContainer, child: Icon(item.isLow ? Icons.warning_amber_rounded : Icons.inventory_2_outlined)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))), if (item.isLow) const Text('منخفض', style: TextStyle(fontWeight: FontWeight.w800))]),
                                const SizedBox(height: 4),
                                Text('${item.location} • الحد الأدنى ${_format(item.minimum)} ${item.unit}', style: Theme.of(context).textTheme.bodySmall),
                              ])),
                              IconButton(onPressed: () => widget.store.changePantryQuantity(item, -1), icon: const Icon(Icons.remove_circle_outline)),
                              Text('${_format(item.quantity)}\n${item.unit}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)),
                              IconButton(onPressed: () => widget.store.changePantryQuantity(item, 1), icon: const Icon(Icons.add_circle_outline)),
                              PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') _showEditor(item); if (v == 'delete') widget.store.deletePantryItem(item); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('تعديل')), PopupMenuItem(value: 'delete', child: Text('حذف'))]),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PantrySummary extends StatelessWidget {
  const _PantrySummary({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Icon(icon), const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), Text(label)])])));
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final names = store.favorites.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('المفضلة', style: TextStyle(fontWeight: FontWeight.w900))),
      body: names.isEmpty
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.star_border, size: 64), SizedBox(height: 12), Text('لا توجد منتجات مفضلة بعد')]))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: names.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) => Card(
                child: ListTile(
                  leading: const Icon(Icons.star),
                  title: Text(names[index], style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(store.categoryFor(names[index])),
                  trailing: IconButton(
                    tooltip: 'إزالة من المفضلة',
                    onPressed: () => store.toggleFavorite(names[index]),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ),
              ),
            ),
    );
  }
}

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final top = store.mostUsedProducts;
    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth > 600 ? (constraints.maxWidth - 24) / 4 : (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(width: width, icon: Icons.shopping_bag_outlined, label: 'رحلات التسوق', value: '${store.totalTrips}'),
                _StatCard(width: width, icon: Icons.check_circle_outline, label: 'أغراض مكتملة', value: '${store.completedItems}'),
                _StatCard(width: width, icon: Icons.list_alt, label: 'إجمالي الأغراض', value: '${store.totalItems}'),
                _StatCard(width: width, icon: Icons.calculate_outlined, label: 'متوسط الرحلة', value: store.averageItemsPerTrip.toStringAsFixed(1)),
              ],
            );
          }),
          const SizedBox(height: 24),
          const Text('الأكثر إضافة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          if (top.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('ستظهر الإحصائيات بعد استخدام التطبيق'))),
          for (var i = 0; i < top.length; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(top[i].key, style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: Text('${top[i].value} مرة'),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.width, required this.icon, required this.label, required this.value});
  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon),
              const SizedBox(height: 16),
              Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              Text(label),
            ]),
          ),
        ),
      );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.w900))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('المظهر', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Card(
              child: Column(children: [
                RadioListTile<ThemeMode>(value: ThemeMode.system, groupValue: store.themeMode, onChanged: (v) => store.setThemeMode(v!), title: const Text('حسب إعداد الجهاز')),
                RadioListTile<ThemeMode>(value: ThemeMode.light, groupValue: store.themeMode, onChanged: (v) => store.setThemeMode(v!), title: const Text('فاتح')),
                RadioListTile<ThemeMode>(value: ThemeMode.dark, groupValue: store.themeMode, onChanged: (v) => store.setThemeMode(v!), title: const Text('داكن')),
              ]),
            ),
            const SizedBox(height: 20),
            const Text('حجم النص', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Slider(value: store.fontScale, min: 0.9, max: 1.25, divisions: 7, label: '${(store.fontScale * 100).round()}٪', onChanged: store.setFontScale),
                  Text('نص تجريبي بحجم ${(store.fontScale * 100).round()}٪', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('مقاضي Sprint 2.5 — المرحلة الثالثة'), subtitle: Text('تحسينات الواجهة، الإحصائيات، المفضلة والإعدادات'))),
          ],
        ),
      );
}

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key, required this.store, required this.list});

  final AppStore store;
  final ShoppingListModel list;

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final controller = TextEditingController();
  String query = '';
  String selectedCategory = 'الكل';
  bool hideDone = false;
  bool favoritesOnly = false;

  List<String> get categories => ['الكل', ...{for (final product in products) product.category}];

  List<Product> get suggestions {
    final normalizedQuery = normalizeArabic(query);
    final result = products.where((product) {
      final matchesCategory = selectedCategory == 'الكل' || product.category == selectedCategory;
      final matchesFavorite = !favoritesOnly || widget.store.favorites.contains(product.name);
      final searchable = normalizeArabic(
        '${product.name} ${product.aliases.join(' ')} ${product.category}',
      );
      final matchesQuery = normalizedQuery.isEmpty ||
          searchTokens(normalizedQuery).every(searchable.contains);
      return matchesCategory && matchesFavorite && matchesQuery;
    }).toList();

    result.sort((a, b) {
      if (normalizedQuery.isNotEmpty) {
        int score(Product product) {
          final name = normalizeArabic(product.name);
          if (name == normalizedQuery) return 3;
          if (name.startsWith(normalizedQuery)) return 2;
          if (name.contains(normalizedQuery)) return 1;
          return 0;
        }
        final scoreCompare = score(b).compareTo(score(a));
        if (scoreCompare != 0) return scoreCompare;
      }
      final aFavorite = widget.store.favorites.contains(a.name) ? 1 : 0;
      final bFavorite = widget.store.favorites.contains(b.name) ? 1 : 0;
      if (aFavorite != bFavorite) return bFavorite.compareTo(aFavorite);
      final aFrequency = widget.store.frequency[a.name] ?? 0;
      final bFrequency = widget.store.frequency[b.name] ?? 0;
      if (aFrequency != bFrequency) return bFrequency.compareTo(aFrequency);
      return a.name.compareTo(b.name);
    });
    return result.take(query.isEmpty ? 18 : 12).toList();
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(() => setState(() => query = controller.text.trim()));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _add(String value, [String? category]) {
    widget.store.addItems(widget.list, value, category);
    controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<GroceryItem>>{};
    for (final item in widget.list.items) {
      if (hideDone && item.done) continue;
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.list.name, style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'خيارات القائمة',
            onSelected: (value) async {
              if (value == 'clearDone') {
                final count = widget.list.completedCount;
                if (count == 0) return;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('حذف المشتريات المنتهية؟'),
                    content: Text('سيتم حذف $count غرض منتهٍ.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                    ],
                  ),
                );
                if (confirmed == true) widget.store.clearCompleted(widget.list);
              }
              if (value == 'reset') widget.store.markAllPending(widget.list);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reset', child: Text('إعادة كل الأغراض للمتبقي')),
              PopupMenuItem(value: 'clearDone', child: Text('حذف المشتريات المنتهية')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(controller.text),
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('تقدم التسوق', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      Text('${(widget.list.progress * 100).round()}٪'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: widget.list.progress),
                    duration: const Duration(milliseconds: 350),
                    builder: (_, value, __) => LinearProgressIndicator(value: value, minHeight: 12, borderRadius: BorderRadius.circular(20)),
                  ),
                  const SizedBox(height: 8),
                  Text('تم ${widget.list.completedCount} • المتبقي ${widget.list.remainingCount}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            onSubmitted: _add,
            decoration: InputDecoration(
              labelText: 'ابحث أو أضف غرضًا',
              hintText: 'مثال: حليب، بيض، خبز',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? const Icon(Icons.add_circle_outline)
                  : IconButton(onPressed: controller.clear, icon: const Icon(Icons.close)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final category = categories[index];
                return FilterChip(
                  label: Text(category),
                  selected: selectedCategory == category,
                  onSelected: (_) => setState(() => selectedCategory = category),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                avatar: const Icon(Icons.star, size: 18),
                label: const Text('المفضلة'),
                selected: favoritesOnly,
                onSelected: (value) => setState(() => favoritesOnly = value),
              ),
              FilterChip(
                avatar: const Icon(Icons.visibility_off, size: 18),
                label: const Text('إخفاء المشتريات'),
                selected: hideDone,
                onSelected: (value) => setState(() => hideDone = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('إضافة سريعة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (query.isNotEmpty && widget.store.exactProduct(query) == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                tileColor: Theme.of(context).colorScheme.secondaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: const Icon(Icons.add),
                title: Text('إضافة "$query"'),
                subtitle: Text('التصنيف المتوقع: ${widget.store.categoryFor(query)}'),
                onTap: () => _add(query),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .map(
                  (product) => InputChip(
                    label: Text(product.name),
                    onPressed: () => _add(product.name, product.category),
                    deleteIcon: Icon(
                      widget.store.favorites.contains(product.name) ? Icons.star : Icons.star_border,
                      size: 18,
                    ),
                    onDeleted: () => widget.store.toggleFavorite(product.name),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          if (widget.list.items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Column(
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 64),
                  SizedBox(height: 10),
                  Text('القائمة فارغة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('أضف أول غرض وابدأ تجهيز مقاضيك'),
                ],
              ),
            ),
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('${entry.value.where((item) => item.done).length}/${entry.value.length}'),
                ],
              ),
            ),
            ...entry.value.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: item.done ? 0.62 : 1,
                  child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    leading: Checkbox(
                      value: item.done,
                      onChanged: (value) {
                        item.done = value ?? false;
                        widget.store.updateItem(widget.list);
                      },
                    ),
                    title: Text(
                      item.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: item.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Text('الكمية: ${item.quantity}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'plus') item.quantity++;
                        if (value == 'minus' && item.quantity > 1) item.quantity--;
                        if (value == 'favorite') widget.store.toggleFavorite(item.name);
                        if (value == 'edit') {
                          final editController = TextEditingController(text: item.name);
                          final newName = await showDialog<String>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('تعديل الغرض'),
                              content: TextField(
                                controller: editController,
                                autofocus: true,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (value) => Navigator.pop(context, value),
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
                                FilledButton(onPressed: () => Navigator.pop(context, editController.text), child: const Text('حفظ')),
                              ],
                            ),
                          );
                          if (newName != null && newName.trim().isNotEmpty) {
                            item.name = newName.trim();
                            item.category = widget.store.categoryFor(item.name);
                            widget.store.updateItem(widget.list);
                          }
                        }
                        if (value == 'delete') {
                          final oldIndex = widget.list.items.indexOf(item);
                          widget.store.removeItem(widget.list, item);
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text('تم حذف ${item.name}'),
                                action: SnackBarAction(
                                  label: 'تراجع',
                                  onPressed: () => widget.store.restoreItem(widget.list, item, oldIndex),
                                ),
                              ),
                            );
                        }
                        if (value != 'favorite' && value != 'delete') widget.store.updateItem(widget.list);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('تعديل الاسم')),
                        const PopupMenuItem(value: 'plus', child: Text('زيادة الكمية')),
                        const PopupMenuItem(value: 'minus', child: Text('تقليل الكمية')),
                        PopupMenuItem(
                          value: 'favorite',
                          child: Text(widget.store.favorites.contains(item.name) ? 'إزالة من المفضلة' : 'إضافة للمفضلة'),
                        ),
                        const PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
