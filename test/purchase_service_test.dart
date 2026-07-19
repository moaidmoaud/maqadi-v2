import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/purchase_repository.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/purchase_service.dart';

void main() {
  late InventoryService inventory;
  late _MemoryPurchaseRepository repository;
  late PurchaseService service;
  late PantryItem rice;
  late PantryItem milk;
  var persistedInventory = 0;

  setUp(() {
    rice = _pantryItem(id: 'rice', name: 'Rice');
    milk = _pantryItem(id: 'milk', name: 'Milk');
    inventory = InventoryService(items: [rice, milk]);
    repository = _MemoryPurchaseRepository();
    persistedInventory = 0;
    service = PurchaseService(
      repository: repository,
      inventoryService: inventory,
      clock: () => DateTime.utc(2026, 7, 19, 12),
      persistInventory: () async => persistedInventory++,
    );
  });

  test('calculates purchase subtotal and total', () {
    final items = [
      _item(productId: rice.id, quantity: 2, unitPrice: 10, finalPrice: 8),
      _item(
        id: 'milk-item',
        productId: milk.id,
        quantity: 1,
        unitPrice: 5,
        finalPrice: 5,
      ),
    ];

    expect(service.calculateSubtotal(items), 25);
    expect(service.calculatePurchaseTotal(items, taxRate: 0.15), 24.15);
  });

  test('calculates item discounts', () {
    final items = [
      _item(productId: rice.id, quantity: 3, unitPrice: 10, finalPrice: 8.5),
    ];

    expect(service.calculateDiscount(items), 4.5);
  });

  test('calculates tax on the discounted amount', () {
    final items = [
      _item(productId: rice.id, quantity: 2, unitPrice: 10, finalPrice: 8),
    ];

    expect(service.calculateTax(items, taxRate: 0.15), 2.4);
  });

  test(
    'creates a purchase and inventory batches through InventoryService',
    () async {
      final expiry = DateTime.utc(2027, 1, 1);
      final purchase = await service.createPurchase(
        id: 'purchase-1',
        storeId: 'store-1',
        purchaseDate: DateTime.utc(2026, 7, 18),
        taxRate: 0.15,
        notes: 'Weekly shop',
        items: [
          _item(
            productId: rice.id,
            quantity: 2,
            unitPrice: 10,
            finalPrice: 8,
            batchId: 'rice-lot',
            expiryDate: expiry,
          ),
          _item(
            id: 'milk-item',
            productId: milk.id,
            quantity: 1,
            unitPrice: 5,
            finalPrice: 5,
          ),
        ],
      );

      expect(purchase.subtotal, 25);
      expect(purchase.discount, 4);
      expect(purchase.tax, 3.15);
      expect(purchase.total, 24.15);
      expect(purchase.notes, 'Weekly shop');
      expect(rice.quantity, 2);
      expect(milk.quantity, 1);
      expect(rice.batches.single.id, 'rice-lot');
      expect(rice.batches.single.expiresAt, expiry);
      expect(rice.batches.single.receivedAt, DateTime.utc(2026, 7, 18));
      expect(inventory.movements.last.type, 'شراء');
      expect(persistedInventory, 1);

      final storedItems = await repository.readPurchaseDetails(purchase.id);
      expect(storedItems, hasLength(2));
      expect(storedItems.every((item) => item.batchId != null), isTrue);
      expect(storedItems.first.lineTotal, 16);
    },
  );

  test('rejects invalid purchases before changing inventory', () async {
    await expectLater(
      service.createPurchase(
        id: 'invalid',
        storeId: 'store-1',
        purchaseDate: DateTime.utc(2026, 7, 19),
        items: [
          _item(productId: rice.id, quantity: 0, unitPrice: 10, finalPrice: 10),
        ],
      ),
      throwsArgumentError,
    );
    expect(rice.quantity, 0);
    expect(await repository.readPurchaseHistory(), isEmpty);
  });

  test(
    'updates and deletes purchase stock without duplicating consumed units',
    () async {
      final created = await service.createPurchase(
        id: 'purchase-1',
        storeId: 'store-1',
        purchaseDate: DateTime.utc(2026, 7, 18),
        items: [
          _item(productId: rice.id, quantity: 5, unitPrice: 10, finalPrice: 10),
        ],
      );
      inventory.consume(rice, 2);
      final details = await service.readPurchaseDetails(created.id);

      final updated = await service.updatePurchase(
        purchase: created.copyWith(notes: 'Corrected'),
        taxRate: 0,
        items: [details.single.copyWith(quantity: 6)],
      );

      expect(updated.notes, 'Corrected');
      expect(rice.quantity, 4);
      expect(
        (await service.readPurchaseDetails(created.id)).single.quantity,
        6,
      );

      await service.deletePurchase(created.id);

      expect(rice.quantity, 0);
      expect(await service.readPurchase(created.id), isNull);
      expect(persistedInventory, 3);
    },
  );
}

PantryItem _pantryItem({required String id, required String name}) =>
    PantryItem(
      id: id,
      name: name,
      category: 'Food',
      minimum: 1,
      unit: 'unit',
      location: 'Pantry',
    );

PurchaseItem _item({
  String id = 'rice-item',
  required String productId,
  required double quantity,
  required double unitPrice,
  required double finalPrice,
  String? batchId,
  DateTime? expiryDate,
}) =>
    PurchaseItem(
      id: id,
      purchaseId: 'draft',
      productId: productId,
      quantity: quantity,
      unitPrice: unitPrice,
      finalUnitPrice: finalPrice,
      lineTotal: 0,
      batchId: batchId,
      expiryDate: expiryDate,
    );

class _MemoryPurchaseRepository implements PurchaseRepository {
  final Map<String, Purchase> purchases = {};
  final Map<String, List<PurchaseItem>> details = {};

  @override
  Future<Purchase> createPurchase(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    if (purchases.containsKey(purchase.id)) throw StateError('duplicate');
    purchases[purchase.id] = purchase;
    details[purchase.id] = List.of(items);
    return purchase;
  }

  @override
  Future<void> deletePurchase(String purchaseId) async {
    purchases.remove(purchaseId);
    details.remove(purchaseId);
  }

  @override
  Future<Purchase?> readPurchase(String purchaseId) async =>
      purchases[purchaseId];

  @override
  Future<List<PurchaseItem>> readPurchaseDetails(String purchaseId) async =>
      List.unmodifiable(details[purchaseId] ?? const []);

  @override
  Future<List<Purchase>> readPurchaseHistory() async =>
      List.unmodifiable(purchases.values);

  @override
  Future<List<Purchase>> readPurchasesByDate(DateTime date) async =>
      purchases.values
          .where(
            (purchase) =>
                purchase.purchaseDate.year == date.year &&
                purchase.purchaseDate.month == date.month &&
                purchase.purchaseDate.day == date.day,
          )
          .toList();

  @override
  Future<List<Purchase>> readPurchasesByStore(String storeId) async =>
      purchases.values
          .where((purchase) => purchase.storeId == storeId)
          .toList();

  @override
  Future<Purchase> updatePurchase(
    Purchase purchase,
    List<PurchaseItem> items,
  ) async {
    if (!purchases.containsKey(purchase.id)) throw StateError('missing');
    purchases[purchase.id] = purchase;
    details[purchase.id] = List.of(items);
    return purchase;
  }
}
