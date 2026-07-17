import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'products.dart';

void main() => runApp(const MaqadiApp());

String normalizeArabic(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي')
    .trim();

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

  final List<ShoppingListModel> lists = [];
  final Set<String> favorites = {};
  final Map<String, int> frequency = {};
  String? lastListId;
  bool isReady = false;

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

    if (rawLists != null) {
      lists.addAll((jsonDecode(rawLists) as List)
          .map((item) => ShoppingListModel.fromJson(Map<String, dynamic>.from(item as Map))));
    }
    favorites.addAll(prefs.getStringList(_favoritesKey) ?? const []);
    if (rawFrequency != null) {
      frequency.addAll(Map<String, dynamic>.from(jsonDecode(rawFrequency) as Map)
          .map((key, value) => MapEntry(key, value as int)));
    }
    lastListId = prefs.getString(_lastListKey);

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

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_listsKey, jsonEncode(lists.map((list) => list.toJson()).toList()));
    await prefs.setStringList(_favoritesKey, favorites.toList());
    await prefs.setString(_frequencyKey, jsonEncode(frequency));
    if (lastListId != null) await prefs.setString(_lastListKey, lastListId!);
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
    save();
    return list;
  }

  void openList(ShoppingListModel list) {
    lastListId = list.id;
    list.updatedAt = DateTime.now();
    notifyListeners();
    save();
  }

  void renameList(ShoppingListModel list, String name) {
    if (name.trim().isEmpty) return;
    list.name = name.trim();
    list.updatedAt = DateTime.now();
    notifyListeners();
    save();
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
    save();
    return copy;
  }

  void archiveList(ShoppingListModel list, bool archived) {
    list.archived = archived;
    list.updatedAt = DateTime.now();
    if (lastListId == list.id) lastListId = activeLists.isEmpty ? null : activeLists.first.id;
    notifyListeners();
    save();
  }

  void deleteList(ShoppingListModel list) {
    lists.removeWhere((item) => item.id == list.id);
    if (lastListId == list.id) lastListId = activeLists.isEmpty ? null : activeLists.first.id;
    notifyListeners();
    save();
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
      save();
    }
  }

  void updateItem(ShoppingListModel list) {
    list.updatedAt = DateTime.now();
    notifyListeners();
    save();
  }

  void removeItem(ShoppingListModel list, GroceryItem item) {
    list.items.remove(item);
    updateItem(list);
  }

  void toggleFavorite(String name) {
    favorites.contains(name) ? favorites.remove(name) : favorites.add(name);
    notifyListeners();
    save();
  }
}

class MaqadiApp extends StatefulWidget {
  const MaqadiApp({super.key});

  @override
  State<MaqadiApp> createState() => _MaqadiAppState();
}

class _MaqadiAppState extends State<MaqadiApp> {
  final AppStore store = AppStore();
  ThemeMode themeMode = ThemeMode.system;

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
          themeMode: themeMode,
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
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: store.isReady
                ? HomeScreen(
                    store: store,
                    onToggleTheme: () => setState(() {
                      themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                    }),
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
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickCard(
                  icon: Icons.bar_chart_outlined,
                  title: 'الإحصائيات',
                  subtitle: '${widget.store.lists.length} قائمة',
                ),
              ),
            ],
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
  const _QuickCard({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Card(
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
      final matchesQuery = normalizedQuery.isEmpty ||
          normalizeArabic(product.name).contains(normalizedQuery) ||
          product.aliases.any((alias) => normalizeArabic(alias).contains(normalizedQuery));
      return matchesCategory && matchesFavorite && matchesQuery;
    }).toList();

    result.sort((a, b) {
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
                  LinearProgressIndicator(value: widget.list.progress, minHeight: 12, borderRadius: BorderRadius.circular(20)),
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
                      onSelected: (value) {
                        if (value == 'plus') item.quantity++;
                        if (value == 'minus' && item.quantity > 1) item.quantity--;
                        if (value == 'favorite') widget.store.toggleFavorite(item.name);
                        if (value == 'delete') widget.store.removeItem(widget.list, item);
                        if (value != 'favorite' && value != 'delete') widget.store.updateItem(widget.list);
                      },
                      itemBuilder: (_) => [
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
          ],
        ],
      ),
    );
  }
}
