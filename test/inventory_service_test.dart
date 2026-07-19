import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/expiry_models.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/shopping_models.dart';
import 'package:maqadi_v2/models/stock_models.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

void main() {
  group('InventoryService', () {
    test('stores multiple batches and consumes them in FIFO order', () {
      var id = 0;
      final service = InventoryService(idFactory: () => 'id_${++id}');
      final firstReceived = DateTime.utc(2026, 1, 1);
      final secondReceived = DateTime.utc(2026, 2, 1);

      final item = service.addStock(
        name: 'أرز',
        category: 'الحبوب',
        quantity: 3,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
        receivedAt: firstReceived,
      );
      final firstBatchId = item.batches.single.id;

      service.addStock(
        name: 'ارز',
        category: 'الحبوب',
        quantity: 5,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
        receivedAt: secondReceived,
      );
      final secondBatchId = item.batches.last.id;

      expect(service.items, hasLength(1));
      expect(item.batches, hasLength(2));
      expect(item.quantity, 8);

      final consumed = service.consume(item, 4);

      expect(consumed, 4);
      expect(item.quantity, 4);
      expect(item.batches, hasLength(1));
      expect(item.batches.single.id, secondBatchId);
      expect(item.batches.single.quantity, 4);
      expect(service.movements.last.amount, -4);
      expect(service.movements.last.batchAllocations, {
        firstBatchId: -3,
        secondBatchId: -1,
      });
    });

    test('quantity edits reconcile batches through FIFO', () {
      var id = 0;
      final service = InventoryService(idFactory: () => 'id_${++id}');
      final item = service.addStock(
        name: 'حليب',
        category: 'الألبان',
        quantity: 2,
        minimum: 1,
        unit: 'حبة',
        location: 'الثلاجة',
      );
      service.addBatch(item, quantity: 3);

      service.updateItem(
        item,
        name: 'حليب كامل الدسم',
        category: 'الألبان',
        quantity: 1,
        minimum: 2,
        unit: 'علبة',
        location: 'الثلاجة',
      );

      expect(item.quantity, 1);
      expect(item.minimum, 2);
      expect(item.unit, 'علبة');
      expect(item.batches, hasLength(1));
      expect(service.movements.last.type, 'تعديل');
      expect(service.movements.last.amount, -4);
    });

    test('batch management keeps totals and FIFO order in the service', () {
      var id = 0;
      final service = InventoryService(idFactory: () => 'id_${++id}');
      final item = service.addStock(
        name: 'قهوة',
        category: 'المشروبات',
        quantity: 0,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
      );
      final newer = service.addBatch(
        item,
        quantity: 3,
        receivedAt: DateTime.utc(2026, 2, 1),
        batchId: 'february',
      );
      final older = service.addBatch(
        item,
        quantity: 2,
        receivedAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2027, 1, 1),
        batchId: 'january',
        note: 'عرض خاص',
      );

      expect(item.quantity, 5);
      expect(service.batchesFor(item), [older, newer]);

      service.updateBatch(
        item,
        older,
        quantity: 4,
        receivedAt: DateTime.utc(2026, 3, 1),
        expiresAt: DateTime.utc(2027, 3, 1),
        batchId: 'march',
        note: 'تم تحديثها',
      );

      expect(item.quantity, 7);
      expect(older.id, 'march');
      expect(older.note, 'تم تحديثها');
      expect(service.batchesFor(item), [newer, older]);
      expect(service.movements.last.type, 'تعديل دفعة');
      expect(service.movements.last.amount, 2);
      expect(service.movements.last.batchAllocations, {'march': 2});

      service.deleteBatch(item, newer);

      expect(item.quantity, 4);
      expect(service.batchesFor(item), [older]);
      expect(service.movements.last.type, 'حذف دفعة');
      expect(service.movements.last.amount, -3);
      expect(service.movements.last.batchAllocations, {'february': -3});
    });

    test('rejects duplicate custom batch identifiers', () {
      final service = InventoryService();
      final item = service.addStock(
        name: 'تمر',
        category: 'الحبوب',
        quantity: 0,
        minimum: 1,
        unit: 'علبة',
        location: 'المخزن',
      );
      service.addBatch(item, quantity: 1, batchId: 'lot-1');

      expect(
        () => service.addBatch(item, quantity: 2, batchId: 'lot-1'),
        throwsArgumentError,
      );
    });
  });

  test('legacy pantry JSON migrates quantity into an opening batch', () {
    final item = PantryItem.fromJson({
      'id': 'legacy-1',
      'name': 'سكر',
      'category': 'المشروبات',
      'quantity': 6,
      'minimum': 2,
      'unit': 'كجم',
      'location': 'المخزن',
    });

    expect(item.quantity, 6);
    expect(item.batches, hasLength(1));
    expect(item.batches.single.id, 'legacy-1_legacy');

    final saved = item.toJson();
    expect(saved['quantity'], 6);
    expect(saved['batches'], isA<List<dynamic>>());
    expect(saved['batches'], hasLength(1));
  });

  test('legacy pantry JSON defaults the minimum stock to one', () {
    final item = PantryItem.fromJson({
      'id': 'legacy-without-minimum',
      'name': 'طحين',
      'category': 'الحبوب',
      'quantity': 2,
      'unit': 'كجم',
      'location': 'المخزن',
    });

    expect(item.minimum, 1);
    expect(item.toJson()['minimum'], 1);
  });

  group('shopping intelligence', () {
    test('calculates out, low, and normal stock boundaries', () {
      final service = InventoryService();
      final outOfStock = service.addStock(
        name: 'حليب',
        category: 'الألبان',
        quantity: 0,
        minimum: 1,
        unit: 'علبة',
        location: 'الثلاجة',
      );
      final lowStock = service.addStock(
        name: 'أرز',
        category: 'الحبوب',
        quantity: 2,
        minimum: 2,
        unit: 'كجم',
        location: 'المخزن',
      );
      final normalStock = service.addStock(
        name: 'تمر',
        category: 'الحبوب',
        quantity: 3,
        minimum: 1,
        unit: 'علبة',
        location: 'المخزن',
      );

      expect(service.stockInfoFor(outOfStock).status, StockStatus.outOfStock);
      expect(service.stockInfoFor(lowStock).status, StockStatus.lowStock);
      expect(service.stockInfoFor(normalStock).status, StockStatus.normalStock);
      expect(
        service.stockItems(StockStatus.lowStock).single.item,
        same(lowStock),
      );
      expect(
        service.stockItems(StockStatus.outOfStock, query: 'حليب').single.item,
        same(outOfStock),
      );
      expect(
        service.pantryItems(needsShoppingOnly: true),
        [outOfStock, lowStock],
      );
      expect(
        service.pantryItems(query: 'تمر', location: 'المخزن'),
        [normalStock],
      );
    });

    test('keeps one automatic shopping item until stock is replenished', () {
      var id = 0;
      final service = InventoryService(idFactory: () => 'inventory_${++id}');
      final item = service.addStock(
        name: 'حليب',
        category: 'الألبان',
        quantity: 0,
        minimum: 1,
        unit: 'علبة',
        location: 'الثلاجة',
      );
      final list = ShoppingListModel(
        id: 'list-1',
        name: 'قائمتي',
        createdAt: DateTime.utc(2026, 7, 19),
        updatedAt: DateTime.utc(2026, 7, 19),
        items: [],
      );

      expect(
        service.synchronizeAutomaticShoppingList(
          list,
          idFactory: () => 'shopping_${++id}',
        ),
        isTrue,
      );
      expect(list.items, hasLength(1));
      expect(list.items.single.pantryItemId, item.id);
      expect(list.items.single.quantity, 2);

      expect(
        service.synchronizeAutomaticShoppingList(
          list,
          idFactory: () => 'shopping_${++id}',
        ),
        isFalse,
      );
      expect(list.items, hasLength(1));

      service.addBatch(item, quantity: 1);
      service.synchronizeAutomaticShoppingList(
        list,
        idFactory: () => 'shopping_${++id}',
      );
      expect(list.items.single.quantity, 1);

      service.addBatch(item, quantity: 1);
      service.synchronizeAutomaticShoppingList(
        list,
        idFactory: () => 'shopping_${++id}',
      );
      expect(list.items, isEmpty);
    });

    test('does not duplicate a manually added shopping item', () {
      final service = InventoryService();
      service.addStock(
        name: 'أرز',
        category: 'الحبوب',
        quantity: 0,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
      );
      final manualItem = GroceryItem(
        id: 'manual-rice',
        name: 'ارز',
        category: 'الحبوب',
      );
      final list = ShoppingListModel(
        id: 'list-1',
        name: 'قائمتي',
        createdAt: DateTime.utc(2026, 7, 19),
        updatedAt: DateTime.utc(2026, 7, 19),
        items: [manualItem],
      );

      service.synchronizeAutomaticShoppingList(
        list,
        idFactory: () => 'automatic-rice',
      );

      expect(list.items, [same(manualItem)]);
      expect(list.items.single.pantryItemId, isNull);
    });

    test('searches, filters, and alphabetizes shopping items', () {
      final service = InventoryService();
      final low = service.addStock(
        name: 'أرز',
        category: 'الحبوب',
        quantity: 1,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
      );
      final out = service.addStock(
        name: 'حليب',
        category: 'الألبان',
        quantity: 0,
        minimum: 1,
        unit: 'علبة',
        location: 'الثلاجة',
      );
      service.addStock(
        name: 'تمر',
        category: 'الحبوب',
        quantity: 3,
        minimum: 1,
        unit: 'علبة',
        location: 'المخزن',
      );
      final list = ShoppingListModel(
        id: 'list-1',
        name: 'قائمتي',
        createdAt: DateTime.utc(2026, 7, 19),
        updatedAt: DateTime.utc(2026, 7, 19),
        items: [
          GroceryItem(id: '3', name: 'تمر', category: 'الحبوب'),
          GroceryItem(
            id: '2',
            name: 'حليب',
            category: 'الألبان',
            pantryItemId: out.id,
          ),
          GroceryItem(
            id: '1',
            name: 'أرز',
            category: 'الحبوب',
            pantryItemId: low.id,
          ),
        ],
      );

      final expectedNames = list.items.map((item) => item.name).toList()
        ..sort();
      expect(
        service.shoppingItemsFor(list).map((item) => item.name),
        expectedNames,
      );
      expect(
        service
            .shoppingItemsFor(list, stockStatus: StockStatus.lowStock)
            .single
            .name,
        'أرز',
      );
      expect(
        service
            .shoppingItemsFor(list, stockStatus: StockStatus.outOfStock)
            .single
            .name,
        'حليب',
      );
      expect(service.shoppingItemsFor(list, query: 'تمر').single.name, 'تمر');
    });

    test('shopping JSON remains compatible with optional pantry metadata', () {
      final legacy = GroceryItem.fromJson({
        'id': 'legacy',
        'name': 'سكر',
        'category': 'الحبوب',
        'done': false,
        'quantity': 1,
      });
      final managed = GroceryItem(
        id: 'managed',
        name: 'سكر',
        category: 'الحبوب',
        pantryItemId: 'pantry-sugar',
      );

      expect(legacy.pantryItemId, isNull);
      expect(
        GroceryItem.fromJson(managed.toJson()).pantryItemId,
        'pantry-sugar',
      );
    });
  });

  group('expiry management', () {
    test('calculates fresh, expiring soon, and expired boundaries', () {
      final service = InventoryService(
        clock: () => DateTime.utc(2026, 7, 19, 23, 45),
      );
      final item = service.addStock(
        name: 'حليب',
        category: 'الألبان',
        quantity: 0,
        minimum: 1,
        unit: 'علبة',
        location: 'الثلاجة',
      );
      final noExpiry = service.addBatch(
        item,
        quantity: 1,
        batchId: 'no-expiry',
      );
      final fresh = service.addBatch(
        item,
        quantity: 1,
        expiresAt: DateTime.utc(2026, 8, 19),
        batchId: 'fresh',
      );
      final soon = service.addBatch(
        item,
        quantity: 1,
        expiresAt: DateTime.utc(2026, 8, 18),
        batchId: 'soon',
      );
      final today = service.addBatch(
        item,
        quantity: 1,
        expiresAt: DateTime.utc(2026, 7, 19),
        batchId: 'today',
      );
      final expired = service.addBatch(
        item,
        quantity: 1,
        expiresAt: DateTime.utc(2026, 7, 18),
        batchId: 'expired',
      );

      expect(service.expiryFor(item, noExpiry).status, BatchExpiryStatus.fresh);
      expect(service.expiryFor(item, noExpiry).daysRemaining, isNull);
      expect(service.expiryFor(item, fresh).status, BatchExpiryStatus.fresh);
      expect(service.expiryFor(item, fresh).daysRemaining, 31);
      expect(
        service.expiryFor(item, soon).status,
        BatchExpiryStatus.expiringSoon,
      );
      expect(service.expiryFor(item, soon).daysRemaining, 30);
      expect(
        service.expiryFor(item, today).status,
        BatchExpiryStatus.expiringSoon,
      );
      expect(service.expiryFor(item, today).daysRemaining, 0);
      expect(
        service.expiryFor(item, expired).status,
        BatchExpiryStatus.expired,
      );
      expect(service.expiryFor(item, expired).daysRemaining, -1);
    });

    test('filters and sorts expiry lists by nearest expiry', () {
      final service = InventoryService(clock: () => DateTime.utc(2026, 7, 19));
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
        expiresAt: DateTime.utc(2026, 7, 29),
        batchId: 'milk-10',
      );
      service.addBatch(
        milk,
        quantity: 1,
        expiresAt: DateTime.utc(2026, 7, 21),
        batchId: 'milk-2',
      );
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
        quantity: 1,
        expiresAt: DateTime.utc(2026, 7, 18),
        batchId: 'rice-expired-1',
      );
      service.addBatch(
        rice,
        quantity: 1,
        expiresAt: DateTime.utc(2026, 7, 10),
        batchId: 'rice-expired-9',
      );

      expect(service.expiringSoonBatches().map((info) => info.batch.id), [
        'milk-2',
        'milk-10',
      ]);
      expect(
        service.expiringSoonBatches(query: 'حليب').map((info) => info.batch.id),
        ['milk-2', 'milk-10'],
      );
      expect(
        service.expiringSoonBatches(query: 'milk-10').single.batch.id,
        'milk-10',
      );
      expect(service.expiredBatches().map((info) => info.batch.id), [
        'rice-expired-1',
        'rice-expired-9',
      ]);
    });
  });
}
