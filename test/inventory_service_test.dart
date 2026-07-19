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
