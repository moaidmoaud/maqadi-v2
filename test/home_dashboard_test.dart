import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/home_dashboard/application/home_dashboard_provider.dart';
import 'package:maqadi_v2/home_dashboard/domain/home_dashboard_data.dart';
import 'package:maqadi_v2/home_dashboard/presentation/home_dashboard_screen.dart';
import 'package:maqadi_v2/models/dashboard_analytics_models.dart';
import 'package:maqadi_v2/models/purchase_models.dart';

void main() {
  test(
      'placeholder monthly savings provider is replaceable and returns no data',
      () async {
    const provider = PlaceholderMonthlySavingsProvider();

    expect(await provider.loadMonthlySavings(), isNull);
  });

  test('existing service provider combines inventory and latest purchase data',
      () async {
    final older = _purchaseEntry(
      id: 'older',
      store: 'Older store',
      date: DateTime.utc(2026, 6, 1),
      itemCount: 2,
    );
    final latest = _purchaseEntry(
      id: 'latest',
      store: 'Latest store',
      date: DateTime.utc(2026, 7, 23),
      itemCount: 4,
    );
    final provider = ExistingServicesHomeDashboardProvider(
      readAnalytics: () => _analytics(products: 12, shopping: 5, lowStock: 3),
      readPurchaseHistory: () async => [latest, older],
    );

    final data = await provider.load();

    expect(data.totalProducts, 12);
    expect(data.pendingShoppingProducts, 5);
    expect(data.lowStockProducts, 3);
    expect(data.monthlySavings, isNull);
    expect(data.lastReceipt?.store, 'Latest store');
    expect(data.lastReceipt?.productCount, 4);
  });

  testWidgets('dashboard renders exactly six primary cards', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_FakeDashboardProvider(_populatedData())));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardCard), findsNWidgets(6));
    expect(find.text('المخزون'), findsOneWidget);
    expect(find.text('قائمة التسوق'), findsOneWidget);
    expect(find.text('مخزون منخفض'), findsOneWidget);
    expect(find.text('التوفير الشهري'), findsOneWidget);
    expect(find.text('آخر إيصال'), findsOneWidget);
    expect(find.text('التقاط إيصال'), findsOneWidget);
    expect(find.text('Tamimi'), findsOneWidget);
    expect(find.textContaining('2026/07/23'), findsOneWidget);
  });

  testWidgets('all dashboard cards invoke their navigation actions',
      (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(
      _app(
        _FakeDashboardProvider(_populatedData()),
        onInventory: () => taps.add('inventory'),
        onShoppingList: () => taps.add('shopping'),
        onLowStock: () => taps.add('low'),
        onMonthlySavings: () => taps.add('savings'),
        onLastReceipt: () => taps.add('receipt'),
        onCaptureReceipt: () => taps.add('capture'),
      ),
    );
    await tester.pumpAndSettle();

    for (final entry in const <MapEntry<String, String>>[
      MapEntry('dashboard-inventory', 'inventory'),
      MapEntry('dashboard-shopping-list', 'shopping'),
      MapEntry('dashboard-low-stock', 'low'),
      MapEntry('dashboard-monthly-savings', 'savings'),
      MapEntry('dashboard-last-receipt', 'receipt'),
      MapEntry('dashboard-capture-receipt', 'capture'),
    ]) {
      final target = find.byKey(ValueKey(entry.key));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
      expect(taps.last, entry.value);
    }
  });

  testWidgets('dashboard displays clear empty states', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        _FakeDashboardProvider(
          const HomeDashboardData(
            totalProducts: 0,
            pendingShoppingProducts: 0,
            lowStockProducts: 0,
            monthlySavings: null,
            lastReceipt: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('لا توجد منتجات'), findsOneWidget);
    expect(find.text('لا توجد منتجات معلقة'), findsOneWidget);
    expect(find.text('لا توجد منتجات تحتاج انتباهًا'), findsOneWidget);
    expect(find.text('قريبًا'), findsOneWidget);
    expect(find.text('لا يوجد إيصال'), findsOneWidget);
  });

  testWidgets('monthly savings placeholder destination is navigable',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: HomeDashboardScreen(
              provider: _FakeDashboardProvider(_populatedData()),
              onInventory: () {},
              onShoppingList: () {},
              onLowStock: () {},
              onMonthlySavings: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const DashboardPlaceholderScreen(
                    title: 'التوفير الشهري',
                    message: 'سيكون ملخص التوفير الشهري متاحًا قريبًا.',
                  ),
                ),
              ),
              onLastReceipt: () {},
              onCaptureReceipt: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final target = find.byKey(const ValueKey('dashboard-monthly-savings'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();

    expect(find.byType(DashboardPlaceholderScreen), findsOneWidget);
    expect(
        find.text('سيكون ملخص التوفير الشهري متاحًا قريبًا.'), findsOneWidget);
  });
}

Widget _app(
  HomeDashboardProvider provider, {
  VoidCallback? onInventory,
  VoidCallback? onShoppingList,
  VoidCallback? onLowStock,
  VoidCallback? onMonthlySavings,
  VoidCallback? onLastReceipt,
  VoidCallback? onCaptureReceipt,
}) =>
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: HomeDashboardScreen(
            provider: provider,
            onInventory: onInventory ?? () {},
            onShoppingList: onShoppingList ?? () {},
            onLowStock: onLowStock ?? () {},
            onMonthlySavings: onMonthlySavings ?? () {},
            onLastReceipt: onLastReceipt ?? () {},
            onCaptureReceipt: onCaptureReceipt ?? () {},
          ),
        ),
      ),
    );

HomeDashboardData _populatedData() => HomeDashboardData(
      totalProducts: 12,
      pendingShoppingProducts: 5,
      lowStockProducts: 3,
      monthlySavings: null,
      lastReceipt: HomeDashboardReceipt(
        store: 'Tamimi',
        date: DateTime.utc(2026, 7, 23),
        productCount: 4,
      ),
    );

DashboardAnalytics _analytics({
  required int products,
  required int shopping,
  required int lowStock,
}) =>
    DashboardAnalytics(
      summary: DashboardSummary(
        totalProducts: products,
        totalBatches: 0,
        totalQuantity: 0,
        lowStock: lowStock,
        outOfStock: 0,
        expiringSoon: 0,
        expired: 0,
        shoppingListItems: shopping,
      ),
      topProducts: const [],
      lowestStockProducts: const [],
      recentlyUpdatedProducts: const [],
      recentlyAddedProducts: const [],
      stockStatusDistribution: const [],
      expiryStatusDistribution: const [],
      categoryDistribution: const [],
    );

PurchaseListEntry _purchaseEntry({
  required String id,
  required String store,
  required DateTime date,
  required int itemCount,
}) =>
    PurchaseListEntry(
      purchase: Purchase(
        id: id,
        storeId: store,
        purchaseDate: date,
        subtotal: 1,
        discount: 0,
        tax: 0,
        total: 1,
        createdAt: date,
        updatedAt: date,
      ),
      itemCount: itemCount,
      storeName: store,
    );

class _FakeDashboardProvider implements HomeDashboardProvider {
  const _FakeDashboardProvider(this.data);

  final HomeDashboardData data;

  @override
  Future<HomeDashboardData> load() async => data;
}
