import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/shared_preferences_purchase_repository.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/purchase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late InventoryService inventory;
  late PurchaseService service;
  late PantryItem rice;
  late PantryItem milk;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rice = _pantryItem('rice', 'Rice');
    milk = _pantryItem('milk', 'Milk');
    inventory = InventoryService(items: [rice, milk]);
    now = DateTime.utc(2026, 7, 20, 10);
    service = PurchaseService(
      repository: SharedPreferencesPurchaseRepository(),
      inventoryService: inventory,
      clock: () => now,
    );
  });

  test(
    'creates amount-based financial snapshots and allocated item totals',
    () async {
      final preview = service.previewTotals(
        [_item('line-1', 'rice', quantity: 2, unitPrice: 10)],
        discount: 5,
        tax: 2,
      );

      expect(preview.subtotal, 20);
      expect(preview.discount, 5);
      expect(preview.tax, 2);
      expect(preview.total, 17);

      final purchase = await service.createPurchase(
        id: 'purchase-1',
        storeId: 'Market',
        purchaseDate: DateTime.utc(2026, 7, 20),
        items: [_item('line-1', 'rice', quantity: 2, unitPrice: 10)],
        discountAmount: 5,
        taxAmount: 2,
      );
      final details = await service.readPurchaseDetails(purchase.id);

      expect(purchase.subtotal, 20);
      expect(purchase.discount, 5);
      expect(purchase.tax, 2);
      expect(purchase.total, 17);
      expect(details.single.finalUnitPrice, 7.5);
      expect(details.single.lineTotal, 15);
      expect(rice.quantity, 2);
    },
  );

  test('validates store items quantity price discount and tax', () async {
    Future<void> create({
      String store = 'Market',
      List<PurchaseItem>? items,
      double discount = 0,
      double tax = 0,
    }) =>
        service.createPurchase(
          id: 'invalid-${items != null && items.isNotEmpty ? items.first.id : 'empty'}-$discount-$tax',
          storeId: store,
          purchaseDate: DateTime.utc(2026, 7, 20),
          items: items ?? const [],
          discountAmount: discount,
          taxAmount: tax,
        );

    await expectLater(
      create(store: ''),
      throwsA(isA<PurchaseValidationException>()),
    );
    await expectLater(create(), throwsA(isA<PurchaseValidationException>()));
    await expectLater(
      create(items: [_item('zero', 'rice', quantity: 0, unitPrice: 1)]),
      throwsA(isA<PurchaseValidationException>()),
    );
    await expectLater(
      create(items: [_item('negative', 'rice', quantity: 1, unitPrice: -1)]),
      throwsA(isA<PurchaseValidationException>()),
    );
    await expectLater(
      create(
        items: [_item('discount', 'rice', quantity: 1, unitPrice: 5)],
        discount: 6,
      ),
      throwsA(isA<PurchaseValidationException>()),
    );
    await expectLater(
      create(items: [_item('tax', 'rice', quantity: 1, unitPrice: 5)], tax: -1),
      throwsA(isA<PurchaseValidationException>()),
    );
    expect(rice.quantity, 0);
    expect(await service.readPurchaseHistory(), isEmpty);
  });

  test('searches and filters history newest first', () async {
    await service.createPurchase(
      id: 'old',
      storeId: 'Alpha Market',
      purchaseDate: DateTime.utc(2026, 7, 10),
      items: [_item('old-line', 'rice', quantity: 1, unitPrice: 4)],
      discountAmount: 0,
      taxAmount: 0,
      notes: 'weekly',
    );
    await service.createPurchase(
      id: 'new',
      storeId: 'Beta Store',
      purchaseDate: DateTime.utc(2026, 7, 18),
      items: [_item('new-line', 'milk', quantity: 1, unitPrice: 7)],
      discountAmount: 0,
      taxAmount: 0,
    );

    expect(
      (await service.searchPurchases()).map((entry) => entry.purchase.id),
      ['new', 'old'],
    );
    expect(
      (await service.searchPurchases(query: 'Milk')).single.purchase.id,
      'new',
    );
    expect(
      (await service.searchPurchases(
        storeId: 'Alpha Market',
      ))
          .single
          .purchase
          .id,
      'old',
    );
    expect(
      (await service.searchPurchases(
        date: DateTime(2026, 7, 18),
      ))
          .single
          .purchase
          .id,
      'new',
    );
    expect(
      (await service.searchPurchases(
        startDate: DateTime(2026, 7, 9),
        endDate: DateTime(2026, 7, 11),
      ))
          .single
          .purchase
          .id,
      'old',
    );
  });

  test(
    'editing uses inventory deltas and preserves financial timestamps',
    () async {
      final created = await service.createPurchase(
        id: 'purchase-1',
        storeId: 'Market',
        purchaseDate: DateTime.utc(2026, 7, 20),
        items: [_item('line-1', 'rice', quantity: 2, unitPrice: 10)],
        discountAmount: 2,
        taxAmount: 1,
      );
      final originalBatch = rice.batches.single;
      now = DateTime.utc(2026, 7, 21, 10);
      final items = await service.readPurchaseDetails(created.id);

      final updated = await service.updatePurchase(
        purchase: created.copyWith(notes: 'Corrected'),
        items: [items.single.copyWith(quantity: 3, unitPrice: 12)],
        discountAmount: 3,
        taxAmount: 2,
      );

      expect(rice.batches, hasLength(1));
      expect(identical(rice.batches.single, originalBatch), isTrue);
      expect(rice.quantity, 3);
      expect(updated.createdAt, created.createdAt);
      expect(updated.updatedAt, now);
      expect(updated.subtotal, 36);
      expect(updated.discount, 3);
      expect(updated.tax, 2);
      expect(updated.total, 35);
    },
  );

  test('safe deletion reverses an untouched purchase batch', () async {
    final purchase = await service.createPurchase(
      id: 'purchase-1',
      storeId: 'Market',
      purchaseDate: DateTime.utc(2026, 7, 20),
      items: [_item('line-1', 'rice', quantity: 2, unitPrice: 5)],
      discountAmount: 0,
      taxAmount: 0,
    );

    await service.deletePurchaseSafely(purchase.id);

    expect(rice.quantity, 0);
    expect(await service.readPurchase(purchase.id), isNull);
  });

  test('safe deletion blocks purchases with consumed inventory', () async {
    final purchase = await service.createPurchase(
      id: 'purchase-1',
      storeId: 'Market',
      purchaseDate: DateTime.utc(2026, 7, 20),
      items: [_item('line-1', 'rice', quantity: 2, unitPrice: 5)],
      discountAmount: 0,
      taxAmount: 0,
    );
    inventory.consume(rice, 1);

    await expectLater(
      service.deletePurchaseSafely(purchase.id),
      throwsA(isA<PurchaseDeletionException>()),
    );

    expect(await service.readPurchase(purchase.id), isNotNull);
    expect(rice.quantity, 1);
  });
}

PantryItem _pantryItem(String id, String name) => PantryItem(
      id: id,
      name: name,
      category: 'Food',
      minimum: 1,
      unit: 'unit',
      location: 'Pantry',
    );

PurchaseItem _item(
  String id,
  String productId, {
  required double quantity,
  required double unitPrice,
}) =>
    PurchaseItem(
      id: id,
      purchaseId: 'draft',
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      finalUnitPrice: unitPrice,
      lineTotal: 0,
    );
