import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/price_history_models.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/price_history_repository.dart';
import 'package:maqadi_v2/repositories/shared_preferences_purchase_repository.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/price_history_service.dart';
import 'package:maqadi_v2/services/purchase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late InventoryService inventory;
  late _MemoryPriceHistoryRepository priceRepository;
  late PriceHistoryService priceHistory;
  late PurchaseService purchases;
  late PantryItem rice;
  late PantryItem milk;
  late PantryItem sugar;
  late PantryItem eggs;
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rice = _pantryItem('rice', 'Rice');
    milk = _pantryItem('milk', 'Milk');
    sugar = _pantryItem('sugar', 'Sugar');
    eggs = _pantryItem('eggs', 'Eggs');
    inventory = InventoryService(items: [rice, milk, sugar, eggs]);
    priceRepository = _MemoryPriceHistoryRepository();
    now = DateTime.utc(2026, 7, 20, 12);
    priceHistory = PriceHistoryService(
      repository: priceRepository,
      clock: () => now,
    );
    purchases = PurchaseService(
      repository: SharedPreferencesPurchaseRepository(),
      inventoryService: inventory,
      priceHistoryService: priceHistory,
      clock: () => now,
    );
  });

  test('successful purchase automatically records final unit price links',
      () async {
    final purchase = await purchases.createPurchase(
      id: 'purchase-1',
      storeId: 'Market',
      purchaseDate: DateTime.utc(2026, 7, 19),
      items: [_item('rice-line', rice.id, quantity: 2, price: 10)],
      discountAmount: 4,
      taxAmount: 0,
    );

    final record = (await priceHistory.historyForProduct(rice.id)).single;
    expect(record.productId, rice.id);
    expect(record.purchaseId, purchase.id);
    expect(record.purchaseItemId, 'rice-line');
    expect(record.storeId, 'Market');
    expect(record.purchaseDate, DateTime.utc(2026, 7, 19));
    expect(record.unitPrice, 8);
    expect(record.currency, 'SAR');
  });

  test('edit keeps unchanged records and replaces only item deltas', () async {
    final created = await purchases.createPurchase(
      id: 'purchase-1',
      storeId: 'Market',
      purchaseDate: DateTime.utc(2026, 7, 19),
      items: [
        _item('rice-line', rice.id, quantity: 1, price: 5),
        _item('milk-line', milk.id, quantity: 1, price: 6),
        _item('sugar-line', sugar.id, quantity: 1, price: 4),
      ],
      discountAmount: 0,
      taxAmount: 0,
    );
    final oldRice = (await priceHistory.historyForProduct(rice.id)).single;
    final oldMilk = (await priceHistory.historyForProduct(milk.id)).single;
    final details = await purchases.readPurchaseDetails(created.id);
    final byId = {for (final item in details) item.id: item};
    now = DateTime.utc(2026, 7, 21, 12);

    await purchases.updatePurchase(
      purchase: created,
      items: [
        byId['rice-line']!,
        byId['milk-line']!.copyWith(unitPrice: 8, finalUnitPrice: 8),
        _item('eggs-line', eggs.id, quantity: 1, price: 7)
            .copyWith(purchaseId: created.id),
      ],
      discountAmount: 0,
      taxAmount: 0,
    );

    final newRice = (await priceHistory.historyForProduct(rice.id)).single;
    final newMilk = (await priceHistory.historyForProduct(milk.id)).single;
    final newEggs = (await priceHistory.historyForProduct(eggs.id)).single;
    expect(newRice.id, oldRice.id);
    expect(newMilk.id, isNot(oldMilk.id));
    expect(newMilk.unitPrice, 8);
    expect(newEggs.purchaseItemId, 'eggs-line');
    expect(await priceHistory.historyForProduct(sugar.id), isEmpty);
    expect(priceRepository.records, hasLength(3));
  });

  test('validated deletion removes only its purchase history', () async {
    final first = await _createPurchase(
      purchases,
      id: 'purchase-1',
      productId: rice.id,
      date: DateTime.utc(2026, 7, 18),
    );
    await _createPurchase(
      purchases,
      id: 'purchase-2',
      productId: rice.id,
      date: DateTime.utc(2026, 7, 19),
    );

    await purchases.deletePurchaseSafely(first.id);

    final remaining = await priceHistory.historyForProduct(rice.id);
    expect(remaining, hasLength(1));
    expect(remaining.single.purchaseId, 'purchase-2');
    expect(await purchases.readPurchase('purchase-1'), isNull);
    expect(await purchases.readPurchase('purchase-2'), isNotNull);
  });

  test('product history is returned newest purchase first', () async {
    await _createPurchase(
      purchases,
      id: 'newer',
      productId: rice.id,
      date: DateTime.utc(2026, 7, 20),
    );
    await _createPurchase(
      purchases,
      id: 'older',
      productId: rice.id,
      date: DateTime.utc(2026, 7, 10),
    );

    expect(
      (await priceHistory.historyForProduct(rice.id))
          .map((record) => record.purchaseId),
      ['newer', 'older'],
    );
  });

  test('history recording failure rolls back purchase and inventory', () async {
    priceRepository.failNextMutation = true;

    await expectLater(
      _createPurchase(
        purchases,
        id: 'purchase-1',
        productId: rice.id,
        date: DateTime.utc(2026, 7, 20),
      ),
      throwsStateError,
    );

    expect(await purchases.readPurchase('purchase-1'), isNull);
    expect(rice.quantity, 0);
    expect(priceRepository.records, isEmpty);
  });

  test('failed edit and blocked delete preserve existing history', () async {
    final created = await _createPurchase(
      purchases,
      id: 'purchase-1',
      productId: rice.id,
      date: DateTime.utc(2026, 7, 20),
      quantity: 2,
    );
    final original = (await priceHistory.historyForProduct(rice.id)).single;
    final details = await purchases.readPurchaseDetails(created.id);
    priceRepository.failNextMutation = true;

    await expectLater(
      purchases.updatePurchase(
        purchase: created,
        items: [details.single.copyWith(unitPrice: 9, finalUnitPrice: 9)],
        discountAmount: 0,
        taxAmount: 0,
      ),
      throwsStateError,
    );
    expect(rice.quantity, 2);
    expect((await purchases.readPurchase(created.id))!.subtotal, 10);
    expect(
        (await priceHistory.historyForProduct(rice.id)).single.id, original.id);

    inventory.consume(rice, 1);
    await expectLater(
      purchases.deletePurchaseSafely(created.id),
      throwsA(isA<PurchaseDeletionException>()),
    );
    expect(
        (await priceHistory.historyForProduct(rice.id)).single.id, original.id);
  });
}

class _MemoryPriceHistoryRepository implements PriceHistoryRepository {
  final List<PriceHistoryRecord> records = [];
  bool failNextMutation = false;

  @override
  Future<void> applyChanges({
    List<PriceHistoryRecord> added = const [],
    Set<String> removedPurchaseItemIds = const {},
  }) async {
    if (failNextMutation) {
      failNextMutation = false;
      throw StateError('price persistence failed');
    }
    records.removeWhere(
      (record) => removedPurchaseItemIds.contains(record.purchaseItemId),
    );
    records.addAll(added);
  }

  @override
  Future<List<PriceHistoryRecord>> readByProduct(String productId) async =>
      records.where((record) => record.productId == productId).toList();

  @override
  Future<List<PriceHistoryRecord>> readByPurchase(String purchaseId) async =>
      records.where((record) => record.purchaseId == purchaseId).toList();

  @override
  Future<void> replacePurchaseRecords(
    String purchaseId,
    List<PriceHistoryRecord> replacements,
  ) async {
    if (failNextMutation) {
      failNextMutation = false;
      throw StateError('price persistence failed');
    }
    records.removeWhere((record) => record.purchaseId == purchaseId);
    records.addAll(replacements);
  }
}

Future<Purchase> _createPurchase(
  PurchaseService service, {
  required String id,
  required String productId,
  required DateTime date,
  double quantity = 1,
}) =>
    service.createPurchase(
      id: id,
      storeId: 'Market',
      purchaseDate: date,
      items: [_item('$id-line', productId, quantity: quantity, price: 5)],
      discountAmount: 0,
      taxAmount: 0,
    );

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
  required double price,
}) =>
    PurchaseItem(
      id: id,
      purchaseId: 'draft',
      productId: productId,
      quantity: quantity,
      unitPrice: price,
      finalUnitPrice: price,
      lineTotal: 0,
    );
