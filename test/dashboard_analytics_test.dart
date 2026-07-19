import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

void main() {
  group('dashboard analytics', () {
    late DateTime now;
    late InventoryService service;

    setUp(() {
      var id = 0;
      now = DateTime.utc(2026, 7, 19, 9);
      service = InventoryService(
        clock: () => now,
        idFactory: () => 'generated_${++id}',
      );
    });

    test('calculates summaries, rankings, and distributions', () {
      final rice = service.addStock(
        name: 'أرز',
        category: 'الحبوب',
        quantity: 0,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
      );
      service.addBatch(
        rice,
        quantity: 6,
        batchId: 'rice-fresh',
        receivedAt: DateTime.utc(2026, 7, 1),
      );
      service.addBatch(
        rice,
        quantity: 4,
        batchId: 'rice-soon',
        receivedAt: DateTime.utc(2026, 7, 2),
        expiresAt: DateTime.utc(2026, 7, 25),
      );

      now = DateTime.utc(2026, 7, 20, 10);
      final milk = service.addStock(
        name: 'حليب',
        category: 'الألبان',
        quantity: 0,
        minimum: 1,
        unit: 'علبة',
        location: 'الثلاجة',
      );
      service.addBatch(
        milk,
        quantity: 1,
        batchId: 'milk-expired',
        expiresAt: DateTime.utc(2026, 7, 18),
      );

      now = DateTime.utc(2026, 7, 21, 11);
      final sugar = service.addStock(
        name: 'سكر',
        category: 'الحبوب',
        quantity: 0,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
      );

      now = DateTime.utc(2026, 7, 22, 12);
      service.updateItem(
        rice,
        name: rice.name,
        category: rice.category,
        quantity: rice.quantity,
        minimum: 2,
        unit: rice.unit,
        location: rice.location,
      );

      final analytics = service.dashboardAnalytics(shoppingListItems: 4);
      final summary = analytics.summary;

      expect(summary.totalProducts, 3);
      expect(summary.totalBatches, 3);
      expect(summary.totalQuantity, 11);
      expect(summary.lowStock, 1);
      expect(summary.outOfStock, 1);
      expect(summary.expiringSoon, 1);
      expect(summary.expired, 1);
      expect(summary.shoppingListItems, 4);
      expect(analytics.topProducts.first.item, same(rice));
      expect(analytics.lowestStockProducts.first.item, same(sugar));
      expect(analytics.recentlyUpdatedProducts.first.item, same(rice));
      expect(analytics.recentlyAddedProducts.first.item, same(sugar));
      expect(
        {
          for (final entry in analytics.stockStatusDistribution)
            entry.label: entry.value,
        },
        {'طبيعي': 1, 'منخفض': 1, 'نافد': 1},
      );
      expect(
        {
          for (final entry in analytics.expiryStatusDistribution)
            entry.label: entry.value,
        },
        {'طازج': 1, 'قريبة خلال 30 يومًا': 1, 'منتهية': 1},
      );
      expect(analytics.categoryDistribution.first.label, 'الحبوب');
      expect(analytics.categoryDistribution.first.value, 2);
    });

    test('caches snapshots and invalidates them after relevant changes', () {
      final item = service.addStock(
        name: 'قهوة',
        category: 'المشروبات',
        quantity: 2,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
      );

      final first = service.dashboardAnalytics(shoppingListItems: 0);
      final cached = service.dashboardAnalytics(shoppingListItems: 0);
      final shoppingChanged = service.dashboardAnalytics(shoppingListItems: 1);

      expect(cached, same(first));
      expect(shoppingChanged, isNot(same(first)));

      service.addBatch(item, quantity: 1, batchId: 'new-batch');
      final inventoryChanged = service.dashboardAnalytics(shoppingListItems: 1);
      expect(inventoryChanged, isNot(same(shoppingChanged)));
      expect(inventoryChanged.summary.totalQuantity, 3);

      now = now.add(const Duration(days: 1));
      final dayChanged = service.dashboardAnalytics(shoppingListItems: 1);
      expect(dayChanged, isNot(same(inventoryChanged)));
    });

    test('global search matches names, categories, and batch identifiers', () {
      final rice = service.addStock(
        name: 'أرز بسمتي',
        category: 'الحبوب',
        quantity: 0,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
      );
      service.addBatch(rice, quantity: 2, batchId: 'LOT-RICE-42');
      service.addStock(
        name: 'حليب',
        category: 'الألبان',
        quantity: 1,
        minimum: 1,
        unit: 'علبة',
        location: 'الثلاجة',
      );

      expect(service.searchDashboard('ارز').single.item, same(rice));
      expect(service.searchDashboard('حبوب').single.item, same(rice));
      final batchResult = service.searchDashboard('lot rice 42').single;
      expect(batchResult.item, same(rice));
      expect(batchResult.matchedBatchIds, ['LOT-RICE-42']);
      expect(batchResult.matchedFields, contains('معرّف الدفعة'));
      expect(service.searchDashboard('غير موجود'), isEmpty);
      expect(service.searchDashboard('   '), isEmpty);
    });
  });
}
