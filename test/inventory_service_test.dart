import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
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
}
