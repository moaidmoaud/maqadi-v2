import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/home_dashboard/application/home_dashboard_provider.dart';
import 'package:maqadi_v2/main.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/shopping_models.dart';
import 'package:maqadi_v2/repositories/app_repository.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

void main() {
  testWidgets('production home renders the six primary dashboard cards', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _dashboardFixture();

    await tester.pumpWidget(_DashboardHost(store: fixture.store));
    await tester.pumpAndSettle();

    for (final title in const [
      'المخزون',
      'قائمة التسوق',
      'مخزون منخفض',
      'التوفير الشهري',
      'آخر إيصال',
      'التقاط إيصال',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    fixture.store.dispose();
  });

  testWidgets('inventory dashboard card opens the production pantry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _dashboardFixture();
    await tester.pumpWidget(_DashboardHost(store: fixture.store));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('dashboard-inventory')));
    await tester.pumpAndSettle();
    expect(find.text('مخزن المنزل'), findsOneWidget);
    expect(find.text('حليب'), findsOneWidget);
    fixture.store.dispose();
  });

  testWidgets('dashboard summary refreshes after an inventory change', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _dashboardFixture();
    await tester.pumpWidget(_DashboardHost(store: fixture.store));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dashboard-low-stock')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    fixture.store.changePantryQuantity(fixture.milk, 2);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('dashboard-low-stock')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    fixture.store.dispose();
  });

  testWidgets('low-stock dashboard card opens the read-only outlook', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _dashboardFixture();
    await tester.pumpWidget(_DashboardHost(store: fixture.store));
    await tester.pumpAndSettle();

    final action = find.byKey(const ValueKey('dashboard-low-stock'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.text('Low stock outlook'), findsOneWidget);
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
            builder: (_, __) => HomeScreen(
              store: store,
              onToggleTheme: () {},
              dashboardProvider: ExistingServicesHomeDashboardProvider(
                readAnalytics: store.dashboardAnalytics,
                readPurchaseHistory: () async => const [],
              ),
            ),
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
