import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/main.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/shopping_models.dart';
import 'package:maqadi_v2/repositories/app_repository.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

void main() {
  testWidgets('dashboard renders summaries, actions, insights, and charts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _dashboardFixture();

    await tester.pumpWidget(_DashboardHost(store: fixture.store));

    for (final title in [
      'إجمالي المنتجات',
      'إجمالي الدفعات',
      'إجمالي الكمية',
      'مخزون منخفض',
      'نفد المخزون',
      'قريب الانتهاء',
      'منتهي الصلاحية',
      'عناصر قائمة التسوق',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    for (final action in ['إضافة منتج', 'قائمة التسوق', 'إدارة الدفعات']) {
      expect(find.text(action), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('dashboard-chart-stock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard-chart-expiry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('dashboard-chart-category')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('dashboard-insight-top')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dashboard-insight-lowest')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('dashboard-insight-updated')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('dashboard-insight-added')),
      findsOneWidget,
    );
    fixture.store.dispose();
  });

  testWidgets('global dashboard search finds a batch and opens its product', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _dashboardFixture();
    await tester.pumpWidget(_DashboardHost(store: fixture.store));

    await tester.enterText(
      find.byKey(const ValueKey('dashboard-global-search')),
      'milk-lot-7',
    );
    await tester.pump();

    final result = find.byKey(ValueKey('dashboard-search-${fixture.milk.id}'));
    expect(result, findsOneWidget);
    expect(
      find.descendant(
        of: result,
        matching: find.textContaining('milk-lot-7'),
      ),
      findsOneWidget,
    );

    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(find.text('دفعات حليب'), findsOneWidget);
    fixture.store.dispose();
  });

  testWidgets('dashboard summary updates after an inventory change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _dashboardFixture();
    await tester.pumpWidget(_DashboardHost(store: fixture.store));

    expect(find.text('3 منتج'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);

    fixture.store.changePantryQuantity(fixture.milk, 2);
    await tester.pump();

    expect(find.text('13'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dashboard-summary-low')),
        matching: find.text('0 منتج'),
      ),
      findsOneWidget,
    );
    fixture.store.dispose();
  });

  testWidgets('batch management quick action opens the product picker', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _dashboardFixture();
    await tester.pumpWidget(_DashboardHost(store: fixture.store));

    final action = find.byKey(const ValueKey('dashboard-action-batches'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.text('اختر منتجًا لإدارة دفعاته'), findsOneWidget);
    fixture.store.dispose();
  });
}

class _DashboardHost extends StatelessWidget {
  const _DashboardHost({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ListenableBuilder(
            listenable: store,
            builder: (_, __) => HomeScreen(store: store, onToggleTheme: () {}),
          ),
        ),
      );
}

_DashboardFixture _dashboardFixture() {
  final inventory = InventoryService(clock: () => DateTime.utc(2026, 7, 19));
  final rice = inventory.addStock(
    name: 'أرز',
    category: 'الحبوب',
    quantity: 10,
    minimum: 1,
    unit: 'كجم',
    location: 'المخزن',
  );
  final milk = inventory.addStock(
    name: 'حليب',
    category: 'الألبان',
    quantity: 0,
    minimum: 1,
    unit: 'علبة',
    location: 'الثلاجة',
  );
  inventory.addBatch(
    milk,
    quantity: 1,
    batchId: 'milk-lot-7',
    expiresAt: DateTime.utc(2026, 7, 20),
  );
  final sugar = inventory.addStock(
    name: 'سكر',
    category: 'الحبوب',
    quantity: 0,
    minimum: 1,
    unit: 'كجم',
    location: 'المخزن',
  );
  final list = ShoppingListModel(
    id: 'list-1',
    name: 'قائمتي',
    createdAt: DateTime.utc(2026, 7, 19),
    updatedAt: DateTime.utc(2026, 7, 19),
    items: [GroceryItem(id: 'shopping-1', name: 'خبز', category: 'المخبوزات')],
  );
  final repository = _MemoryRepository(
    AppData(lists: [list], lastListId: list.id),
  );
  final store = AppStore(repository: repository, inventoryService: inventory)
    ..lists.add(list)
    ..lastListId = list.id;
  return _DashboardFixture(store: store, rice: rice, milk: milk, sugar: sugar);
}

class _DashboardFixture {
  const _DashboardFixture({
    required this.store,
    required this.rice,
    required this.milk,
    required this.sugar,
  });

  final AppStore store;
  final PantryItem rice;
  final PantryItem milk;
  final PantryItem sugar;
}

class _MemoryRepository implements AppRepository {
  _MemoryRepository(this.data);

  final AppData data;

  @override
  Future<AppData> load() async => data;

  @override
  Future<void> save(AppData data) async {}
}
