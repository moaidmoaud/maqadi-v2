import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/main.dart';
import 'package:maqadi_v2/models/expiry_models.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/screens/expiry_list_screen.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/widgets/expiry_status_badge.dart';

void main() {
  testWidgets('expiry badges use status colors and remaining-day labels', (
    tester,
  ) async {
    final service = InventoryService(clock: () => DateTime.utc(2026, 7, 19));
    final item = service.addStock(
      name: 'حليب',
      category: 'الألبان',
      quantity: 0,
      minimum: 1,
      unit: 'علبة',
      location: 'الثلاجة',
    );
    final fresh = service.addBatch(
      item,
      quantity: 1,
      expiresAt: DateTime.utc(2026, 9, 1),
      batchId: 'fresh',
    );
    final soon = service.addBatch(
      item,
      quantity: 1,
      expiresAt: DateTime.utc(2026, 7, 24),
      batchId: 'soon',
    );
    final expired = service.addBatch(
      item,
      quantity: 1,
      expiresAt: DateTime.utc(2026, 7, 17),
      batchId: 'expired',
    );

    Future<void> pumpBadge(BatchExpiryInfo info) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ExpiryStatusBadge(info: info)),
          ),
        );

    await pumpBadge(service.expiryFor(item, fresh));
    expect(find.text('طازج • متبقي 44 يوم'), findsOneWidget);
    expect(_badgeColor(tester), ExpiryStatusBadge.freshBackground);

    await pumpBadge(service.expiryFor(item, soon));
    expect(find.text('قريب الانتهاء • متبقي 5 يوم'), findsOneWidget);
    expect(_badgeColor(tester), ExpiryStatusBadge.expiringSoonBackground);

    await pumpBadge(service.expiryFor(item, expired));
    expect(find.text('منتهي • منذ 2 يوم'), findsOneWidget);
    expect(_badgeColor(tester), ExpiryStatusBadge.expiredBackground);
  });

  testWidgets('expiry screen searches, sorts, and opens the product', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final inventory = InventoryService(clock: () => DateTime.utc(2026, 7, 19));
    final rice = _addExpiringProduct(
      inventory,
      name: 'أرز',
      batchId: 'rice-10',
      expiresAt: DateTime.utc(2026, 7, 29),
    );
    final milk = _addExpiringProduct(
      inventory,
      name: 'حليب',
      batchId: 'milk-2',
      expiresAt: DateTime.utc(2026, 7, 21),
    );
    final store = AppStore(inventoryService: inventory);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ExpiryListScreen(
            store: store,
            status: BatchExpiryStatus.expiringSoon,
          ),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.text(milk.name)).dy,
      lessThan(tester.getTopLeft(find.text(rice.name)).dy),
    );

    await tester.enterText(
      find.byKey(const ValueKey('expiry-search-field')),
      'حليب',
    );
    await tester.pump();
    final milkResult = find.descendant(
      of: find.byType(Card),
      matching: find.text('حليب'),
    );
    expect(milkResult, findsOneWidget);
    expect(find.text('أرز'), findsNothing);

    await tester.tap(milkResult);
    await tester.pumpAndSettle();
    expect(find.text('دفعات حليب'), findsOneWidget);
  });

  testWidgets('expired screen and dashboard show service-owned counts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final inventory = InventoryService(clock: () => DateTime.utc(2026, 7, 19));
    _addExpiringProduct(
      inventory,
      name: 'لبن',
      batchId: 'soon',
      expiresAt: DateTime.utc(2026, 7, 20),
    );
    _addExpiringProduct(
      inventory,
      name: 'جبن',
      batchId: 'expired',
      expiresAt: DateTime.utc(2026, 7, 18),
    );
    final store = AppStore(inventoryService: inventory);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ExpiryListScreen(
            store: store,
            status: BatchExpiryStatus.expired,
          ),
        ),
      ),
    );
    expect(find.text('منتهي الصلاحية'), findsOneWidget);
    expect(find.text('جبن'), findsOneWidget);
    expect(find.text('لبن'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: HomeScreen(store: store, onToggleTheme: () {}),
        ),
      ),
    );
    expect(find.text('قريب الانتهاء'), findsOneWidget);
    expect(find.text('منتهي الصلاحية'), findsOneWidget);
    expect(find.text('1 دفعة'), findsNWidgets(2));
  });
}

Color? _badgeColor(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.byKey(const ValueKey('expiry-status-badge')),
  );
  return (container.decoration! as BoxDecoration).color;
}

PantryItem _addExpiringProduct(
  InventoryService inventory, {
  required String name,
  required String batchId,
  required DateTime expiresAt,
}) {
  final item = inventory.addStock(
    name: name,
    category: 'أخرى',
    quantity: 0,
    minimum: 1,
    unit: 'حبة',
    location: 'المخزن',
  );
  inventory.addBatch(item, quantity: 1, batchId: batchId, expiresAt: expiresAt);
  return item;
}
