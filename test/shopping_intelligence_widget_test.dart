import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/main.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/shopping_models.dart';
import 'package:maqadi_v2/models/stock_models.dart';
import 'package:maqadi_v2/repositories/app_repository.dart';
import 'package:maqadi_v2/screens/batch_management_screen.dart';

void main() {
  testWidgets('product screen shows quantities and a low stock badge', (
    tester,
  ) async {
    final item = PantryItem(
      id: 'pantry-rice',
      name: 'أرز',
      category: 'الحبوب',
      minimum: 2,
      unit: 'كجم',
      location: 'المخزن',
      quantity: 1,
    );
    final store = await _loadedStore(pantry: [item]);

    await tester.pumpWidget(
      MaterialApp(
        home: BatchManagementScreen(store: store, item: item),
      ),
    );

    expect(find.text('الكمية الحالية'), findsOneWidget);
    expect(find.text('الحد الأدنى'), findsOneWidget);
    expect(find.text('1 كجم'), findsAtLeastNWidgets(1));
    expect(find.text('2 كجم'), findsOneWidget);
    expect(find.text('مخزون منخفض'), findsOneWidget);
    final badge = tester.widget<Container>(
      find.byKey(const Key('stock-status-badge')),
    );
    expect((badge.decoration! as BoxDecoration).color, const Color(0xFFFFF8E1));
    store.dispose();
  });

  testWidgets('shopping screen searches and filters by stock status', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rice = PantryItem(
      id: 'pantry-rice',
      name: 'أرز',
      category: 'الحبوب',
      minimum: 1,
      unit: 'كجم',
      location: 'المخزن',
      quantity: 1,
    );
    final milk = PantryItem(
      id: 'pantry-milk',
      name: 'حليب',
      category: 'الألبان',
      minimum: 1,
      unit: 'علبة',
      location: 'الثلاجة',
    );
    final dates = PantryItem(
      id: 'pantry-dates',
      name: 'تمر',
      category: 'الحبوب',
      minimum: 1,
      unit: 'علبة',
      location: 'المخزن',
      quantity: 3,
    );
    final list = ShoppingListModel(
      id: 'list-1',
      name: 'قائمتي',
      createdAt: DateTime.utc(2026, 7, 19),
      updatedAt: DateTime.utc(2026, 7, 19),
      items: [
        GroceryItem(id: 'rice', name: 'أرز', category: 'الحبوب'),
        GroceryItem(id: 'milk', name: 'حليب', category: 'الألبان'),
        GroceryItem(id: 'dates', name: 'تمر', category: 'الحبوب'),
      ],
    );
    final store = await _loadedStore(
      lists: [list],
      pantry: [rice, milk, dates],
      lastListId: list.id,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ShoppingScreen(
          store: store,
          list: list,
          initialStockFilter: StockStatus.lowStock,
        ),
      ),
    );

    expect(_shoppingItemText('rice', 'أرز'), findsOneWidget);
    expect(_shoppingItemText('milk', 'حليب'), findsNothing);
    expect(_shoppingItemText('dates', 'تمر'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'نفد المخزون'));
    await tester.pump();
    expect(_shoppingItemText('milk', 'حليب'), findsOneWidget);
    expect(_shoppingItemText('rice', 'أرز'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'كل المخزون'));
    await tester.enterText(
      find.byKey(const Key('shopping-search-field')),
      'تمر',
    );
    await tester.pump();
    expect(_shoppingItemText('dates', 'تمر'), findsOneWidget);
    expect(_shoppingItemText('milk', 'حليب'), findsNothing);
    store.dispose();
  });

  testWidgets('dashboard shows all shopping intelligence summaries', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final list = ShoppingListModel(
      id: 'list-1',
      name: 'قائمتي',
      createdAt: DateTime.utc(2026, 7, 19),
      updatedAt: DateTime.utc(2026, 7, 19),
    );
    final store = await _loadedStore(
      lists: [list],
      pantry: [
        PantryItem(
          id: 'low',
          name: 'أرز',
          category: 'الحبوب',
          minimum: 1,
          unit: 'كجم',
          location: 'المخزن',
          quantity: 1,
        ),
        PantryItem(
          id: 'out',
          name: 'حليب',
          category: 'الألبان',
          minimum: 1,
          unit: 'علبة',
          location: 'الثلاجة',
        ),
      ],
      lastListId: list.id,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(store: store, onToggleTheme: () {}),
      ),
    );

    expect(find.text('مخزون منخفض'), findsOneWidget);
    expect(find.text('نفد المخزون'), findsOneWidget);
    expect(find.text('عناصر قائمة التسوق'), findsOneWidget);
    store.dispose();
  });
}

Finder _shoppingItemText(String id, String text) => find.descendant(
      of: find.byKey(ValueKey('shopping-item-$id')),
      matching: find.text(text),
    );

Future<AppStore> _loadedStore({
  List<ShoppingListModel>? lists,
  List<PantryItem>? pantry,
  String? lastListId,
}) async {
  final store = AppStore(
    repository: _MemoryRepository(
      AppData(lists: lists, pantry: pantry, lastListId: lastListId),
    ),
  );
  await store.load();
  return store;
}

class _MemoryRepository implements AppRepository {
  _MemoryRepository(this.data);

  final AppData data;

  @override
  Future<AppData> load() async => data;

  @override
  Future<void> save(AppData data) async {}
}
