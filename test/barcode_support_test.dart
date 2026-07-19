import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/barcode_models.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

void main() {
  test('legacy pantry JSON migrates barcode fields without data loss', () {
    final withoutBarcode = PantryItem.fromJson({
      'id': 'legacy-1',
      'name': 'سكر',
      'category': 'الحبوب',
      'quantity': 2,
      'minimum': 1,
      'unit': 'كجم',
      'location': 'المخزن',
    });
    final legacyBarcode = PantryItem.fromJson({
      'id': 'legacy-2',
      'name': 'حليب',
      'category': 'الألبان',
      'quantity': 1,
      'minimum': 1,
      'unit': 'علبة',
      'location': 'الثلاجة',
      'barcode': ' 0123456789 ',
      'additionalBarcodes': ['MILK-2', 'MILK-2', ''],
    });

    expect(withoutBarcode.primaryBarcode, isNull);
    expect(withoutBarcode.additionalBarcodes, isEmpty);
    expect(legacyBarcode.primaryBarcode, '0123456789');
    expect(legacyBarcode.additionalBarcodes, ['MILK-2']);
    expect(legacyBarcode.quantity, 1);
    expect(legacyBarcode.toJson()['primaryBarcode'], '0123456789');
    expect(legacyBarcode.toJson()['additionalBarcodes'], ['MILK-2']);
  });

  group('barcode lookup', () {
    late InventoryService service;
    late PantryItem milk;
    late PantryItem rice;

    setUp(() {
      service = InventoryService();
      milk = service.addStock(
        name: 'حليب',
        category: 'الألبان',
        quantity: 1,
        minimum: 1,
        unit: 'علبة',
        location: 'الثلاجة',
      );
      rice = service.addStock(
        name: 'أرز',
        category: 'الحبوب',
        quantity: 2,
        minimum: 1,
        unit: 'كجم',
        location: 'المخزن',
      );
    });

    test('finds primary and additional barcodes after normalization', () {
      service.setBarcodes(
        milk,
        primaryBarcode: ' 0123 456 ',
        additionalBarcodes: ['MILK-ABC', 'milk-abc', '789'],
      );

      expect(service.findByBarcode('0123456'), same(milk));
      expect(service.findByBarcode('milk-abc'), same(milk));
      expect(service.findByBarcode(' 789 '), same(milk));
      expect(milk.additionalBarcodes, ['MILK-ABC', '789']);
    });

    test('adds, promotes, removes, and rejects duplicate barcodes', () {
      service.setBarcodes(milk, primaryBarcode: '111');
      expect(service.addBarcode(milk, '222'), isTrue);
      expect(service.addBarcode(milk, '222'), isFalse);
      expect(service.makePrimaryBarcode(milk, '222'), isTrue);
      expect(milk.primaryBarcode, '222');
      expect(milk.additionalBarcodes, ['111']);

      expect(
        () => service.setBarcodes(rice, primaryBarcode: ' 222 '),
        throwsArgumentError,
      );
      expect(service.removeBarcode(milk, '111'), isTrue);
      expect(service.findByBarcode('111'), isNull);
      expect(service.findByBarcode('222'), same(milk));
    });
  });

  test('generates and resolves product and batch QR payloads', () {
    final service = InventoryService();
    final item = service.addStock(
      name: 'قهوة',
      category: 'المشروبات',
      quantity: 0,
      minimum: 1,
      unit: 'كجم',
      location: 'المخزن',
    );
    final batch = service.addBatch(
      item,
      quantity: 2,
      batchId: 'lot/2026 01',
    );

    final productPayload = service.productQrPayload(item);
    final batchPayload = service.batchQrPayload(item, batch);
    final productTarget = service.resolveInternalQr(productPayload)!;
    final batchTarget = service.resolveInternalQr(batchPayload)!;

    expect(productTarget.item, same(item));
    expect(productTarget.batch, isNull);
    expect(batchTarget.item, same(item));
    expect(batchTarget.batch, same(batch));
    expect(service.resolveInternalQr('https://example.com'), isNull);
    expect(service.resolveInternalQr('maqadi://product/missing'), isNull);
  });

  test('resolves scanned QR, known barcode, and unknown codes', () {
    final service = InventoryService();
    final item = service.addStock(
      name: 'تمر',
      category: 'الحبوب',
      quantity: 1,
      minimum: 1,
      unit: 'علبة',
      location: 'المخزن',
    );
    service.setBarcodes(item, primaryBarcode: 'DATES-123');

    final qr = service.resolveScan(service.productQrPayload(item));
    final barcode = service.resolveScan(' dates-123 ');
    final unknown = service.resolveScan('UNKNOWN-999');

    expect(qr.type, InventoryScanResultType.internalQr);
    expect(qr.item, same(item));
    expect(barcode.type, InventoryScanResultType.barcode);
    expect(barcode.item, same(item));
    expect(unknown.type, InventoryScanResultType.unknown);
    expect(unknown.item, isNull);
  });

  test('global dashboard search includes barcodes and batch IDs', () {
    final service = InventoryService();
    final item = service.addStock(
      name: 'عصير',
      category: 'المشروبات',
      quantity: 0,
      minimum: 1,
      unit: 'علبة',
      location: 'الثلاجة',
    );
    service.setBarcodes(
      item,
      primaryBarcode: 'JUICE-PRIMARY-7',
      additionalBarcodes: ['JUICE-ALT-8'],
    );
    service.addBatch(item, quantity: 1, batchId: 'JUICE-LOT-9');

    final primary = service.searchDashboard('juice primary 7').single;
    final additional = service.searchDashboard('juice alt 8').single;
    final batch = service.searchDashboard('juice lot 9').single;

    expect(primary.item, same(item));
    expect(primary.matchedBarcodes, ['JUICE-PRIMARY-7']);
    expect(additional.matchedBarcodes, ['JUICE-ALT-8']);
    expect(batch.matchedBatchIds, ['JUICE-LOT-9']);
  });
}
