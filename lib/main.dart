import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MaqadiApp());

class MaqadiApp extends StatefulWidget {
  const MaqadiApp({super.key});
  @override
  State<MaqadiApp> createState() => _MaqadiAppState();
}

class _MaqadiAppState extends State<MaqadiApp> {
  ThemeMode _mode = ThemeMode.system;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مقاضي',
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2E7D32),
        scaffoldBackgroundColor: const Color(0xFFF7F8F6),
        fontFamilyFallback: const ['Arial'],
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF66BB6A),
          brightness: Brightness.dark,
        ),
      ),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: HomePage(
          onToggleTheme: () => setState(() {
            _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
          }),
        ),
      ),
    );
  }
}

class GroceryItem {
  GroceryItem({required this.name, required this.category, this.done = false, this.qty = 1});
  String name;
  String category;
  bool done;
  int qty;

  Map<String, dynamic> toJson() => {'name': name, 'category': category, 'done': done, 'qty': qty};
  factory GroceryItem.fromJson(Map<String, dynamic> j) => GroceryItem(
        name: j['name'] as String,
        category: j['category'] as String,
        done: j['done'] as bool? ?? false,
        qty: j['qty'] as int? ?? 1,
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.onToggleTheme});
  final VoidCallback onToggleTheme;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _key = 'maqadi_items_v2';
  final _controller = TextEditingController();
  final List<GroceryItem> _items = [];
  bool _hideDone = false;

  final Map<String, List<String>> _keywords = const {
    'الخضار والفواكه': ['طماطم','خيار','خس','بصل','ثوم','جزر','كوسا','بقدونس','كزبرة','فطر','بروكلي','قرنبيط','سبانخ','موز','تفاح','برتقال'],
    'الألبان والبيض': ['حليب','لبن','لبنة','زبادي','جبن','بيض','قشطة','زبدة'],
    'اللحوم والدواجن': ['دجاج','صدور دجاج','لحم','لحم مفروم'],
    'الأسماك': ['سلمون','هامور','تونة','سمك'],
    'الأرز والمعكرونة': ['أرز','رز','مكرونة','سباغيتي','شعيرية'],
    'المخبوزات': ['خبز','توست','صامولي'],
    'المعلبات': ['فول','حمص','ذرة','صلصة'],
    'المنظفات والورقيات': ['مناديل','كلور','صابون','منظف','سفرة','أكياس'],
  };

  final _quick = const ['حليب','بيض','خبز','ماء','دجاج','أرز','بصل','طماطم'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return;
    final data = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    setState(() => _items
      ..clear()
      ..addAll(data.map(GroceryItem.fromJson)));
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  String _categoryFor(String name) {
    final n = name.trim();
    for (final entry in _keywords.entries) {
      if (entry.value.any((k) => n.contains(k))) return entry.key;
    }
    return 'أخرى';
  }

  void _add(String raw) {
    final names = raw.split(RegExp(r'[\n,،]+')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    var changed = false;
    for (final name in names) {
      if (_items.any((e) => e.name == name)) continue;
      _items.add(GroceryItem(name: name, category: _categoryFor(name)));
      changed = true;
    }
    if (changed) {
      _controller.clear();
      setState(() {});
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _items.where((e) => e.done).length;
    final total = _items.length;
    final progress = total == 0 ? 0.0 : done / total;
    final grouped = <String, List<GroceryItem>>{};
    for (final item in _items) {
      if (_hideDone && item.done) continue;
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('مقاضي', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: widget.onToggleTheme, icon: const Icon(Icons.dark_mode_outlined))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(_controller.text),
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('قائمة هذا الأسبوع', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: progress, minHeight: 10, borderRadius: BorderRadius.circular(20)),
                  const SizedBox(height: 8),
                  Text('تم شراء $done من $total • المتبقي ${total - done}'),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              onSubmitted: _add,
              decoration: InputDecoration(
                labelText: 'اكتب غرضًا أو الصق قائمة كاملة',
                hintText: 'مثال: حليب، بيض، خبز',
                prefixIcon: const Icon(Icons.shopping_basket_outlined),
                suffixIcon: IconButton(icon: const Icon(Icons.add_circle), onPressed: () => _add(_controller.text)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 14),
            const Text('إضافة سريعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: _quick.map((q) => ActionChip(label: Text(q), onPressed: () => _add(q))).toList()),
            const SizedBox(height: 14),
            SwitchListTile(
              value: _hideDone,
              onChanged: (v) => setState(() => _hideDone = v),
              title: const Text('إخفاء المشتريات'),
              secondary: const Icon(Icons.visibility_off_outlined),
            ),
            if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 36),
                child: Column(children: [Icon(Icons.shopping_cart_outlined, size: 64), SizedBox(height: 12), Text('قائمتك فارغة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text('أضف أول غرض وابدأ التسوق')]),
              ),
            for (final entry in grouped.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 6),
                child: Text(entry.key, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              ...entry.value.map((item) => Card(
                    child: ListTile(
                      leading: Checkbox(
                        value: item.done,
                        onChanged: (v) { setState(() => item.done = v ?? false); _save(); },
                      ),
                      title: Text(item.name, style: TextStyle(decoration: item.done ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w600)),
                      subtitle: Text('الكمية: ${item.qty}'),
                      trailing: SizedBox(
                        width: 122,
                        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          IconButton(onPressed: () { if (item.qty > 1) { setState(() => item.qty--); _save(); } }, icon: const Icon(Icons.remove_circle_outline)),
                          Text('${item.qty}'),
                          IconButton(onPressed: () { setState(() => item.qty++); _save(); }, icon: const Icon(Icons.add_circle_outline)),
                          IconButton(onPressed: () { setState(() => _items.remove(item)); _save(); }, icon: const Icon(Icons.delete_outline)),
                        ]),
                      ),
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
