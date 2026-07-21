import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/price_history_models.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/price_history_repository.dart';
import 'package:maqadi_v2/repositories/purchase_repository.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/price_history_service.dart';
import 'package:maqadi_v2/services/purchase_service.dart';

void main() {
  test(
    'failure after an inventory mutation restores the complete snapshot',
    () async {
      final rice = _pantry('rice');
      final milk = _pantry('milk');
      final inventory = _FailingInventoryService(
        items: [rice, milk],
        failOnAddCall: 2,
      );
      final purchases = _FaultPurchaseRepository();
      final service = PurchaseService(
        repository: purchases,
        inventoryService: inventory,
        clock: _clock,
      );

      await expectLater(
        service.createPurchase(
          id: 'purchase-inventory-failure',
          storeId: 'store',
          purchaseDate: _clock(),
          items: [_item('rice-item', rice.id), _item('milk-item', milk.id)],
        ),
        throwsStateError,
      );

      expect(rice.quantity, 0);
      expect(milk.quantity, 0);
      expect(inventory.movements, isEmpty);
      expect(await purchases.readPurchaseHistory(), isEmpty);
    },
  );

  test(
    'failure after the purchase write removes purchase and inventory',
    () async {
      final rice = _pantry('rice');
      final inventory = InventoryService(items: [rice]);
      final purchases = _FaultPurchaseRepository()..failAfterCreate = true;
      final service = PurchaseService(
        repository: purchases,
        inventoryService: inventory,
        clock: _clock,
      );

      await expectLater(
        _create(service, id: 'purchase-write-failure', productId: rice.id),
        throwsStateError,
      );

      expect(rice.quantity, 0);
      expect(inventory.movements, isEmpty);
      expect(await purchases.readPurchaseHistory(), isEmpty);
    },
  );

  test(
    'failure after price-history write restores every participant',
    () async {
      final rice = _pantry('rice');
      final inventory = InventoryService(items: [rice]);
      final purchases = _FaultPurchaseRepository();
      final prices = _FaultPriceHistoryRepository()..failAfterApply = true;
      final service = PurchaseService(
        repository: purchases,
        inventoryService: inventory,
        priceHistoryService: PriceHistoryService(
          repository: prices,
          clock: _clock,
        ),
        clock: _clock,
      );

      await expectLater(
        _create(service, id: 'price-write-failure', productId: rice.id),
        throwsStateError,
      );

      expect(rice.quantity, 0);
      expect(inventory.movements, isEmpty);
      expect(await purchases.readPurchaseHistory(), isEmpty);
      expect(prices.records, isEmpty);
    },
  );

  test(
    'inventory persistence failure restores all durable participants',
    () async {
      final rice = _pantry('rice');
      final inventory = InventoryService(items: [rice]);
      final purchases = _FaultPurchaseRepository();
      final prices = _FaultPriceHistoryRepository();
      var persistenceCalls = 0;
      final service = PurchaseService(
        repository: purchases,
        inventoryService: inventory,
        priceHistoryService: PriceHistoryService(
          repository: prices,
          clock: _clock,
        ),
        persistInventory: () async {
          persistenceCalls++;
          if (persistenceCalls == 1) throw StateError('inventory persistence');
        },
        clock: _clock,
      );

      await expectLater(
        _create(service, id: 'persistence-failure', productId: rice.id),
        throwsStateError,
      );

      expect(persistenceCalls, 2);
      expect(rice.quantity, 0);
      expect(await purchases.readPurchaseHistory(), isEmpty);
      expect(prices.records, isEmpty);
    },
  );

  test('purchase writes are serialized', () async {
    final rice = _pantry('rice');
    final inventory = InventoryService(items: [rice]);
    final purchases = _FaultPurchaseRepository()
      ..createBarrier = Completer<void>();
    final service = PurchaseService(
      repository: purchases,
      inventoryService: inventory,
      clock: _clock,
    );

    final first = _create(service, id: 'first', productId: rice.id);
    await Future<void>.delayed(Duration.zero);
    final second = _create(service, id: 'second', productId: rice.id);
    await Future<void>.delayed(Duration.zero);

    expect(purchases.createCalls, 1);
    purchases.createBarrier!.complete();
    await Future.wait([first, second]);
    expect(purchases.maximumConcurrentCreates, 1);
    expect(await purchases.readPurchaseHistory(), hasLength(2));
  });
}

DateTime _clock() => DateTime.utc(2026, 7, 21, 12);

Future<Purchase> _create(
  PurchaseService service, {
  required String id,
  required String productId,
}) =>
    service.createPurchase(
      id: id,
      storeId: 'store',
      purchaseDate: _clock(),
      items: [_item('$id-item', productId)],
    );

PantryItem _pantry(String id) => PantryItem(
      id: id,
      name: id,
      category: 'Food',
      minimum: 1,
      unit: 'unit',
      location: 'Pantry',
    );

PurchaseItem _item(String id, String productId) => PurchaseItem(
      id: id,
      purchaseId: 'draft',
      productId: productId,
      quantity: 1,
      unitPrice: 5,
      finalUnitPrice: 5,
      lineTotal: 5,
    );

class _FailingInventoryService extends InventoryService {
  _FailingInventoryService({required super.items, required this.failOnAddCall});

  final int failOnAddCall;
  int addCalls = 0;

  @override
  InventoryBatch addBatch(
    PantryItem item, {
    required double quantity,
    DateTime? receivedAt,
    DateTime? expiresAt,
    String? batchId,
    String? note,
    String movementType = 'إضافة',
  }) {
    addCalls++;
    if (addCalls == failOnAddCall) throw StateError('inventory mutation');
    return super.addBatch(
      item,
      quantity: quantity,
      receivedAt: receivedAt,
      expiresAt: expiresAt,
      batchId: batchId,
      note: note,
      movementType: movementType,
    );
  }
}

class _FaultPurchaseRepository implements PurchaseRepository {
  final Map<String, Purchase> purchases = {};
  final Map<String, List<PurchaseItem>> items = {};
  bool failAfterCreate = false;
  Completer<void>? createBarrier;
  int createCalls = 0;
  int _activeCreates = 0;
  int maximumConcurrentCreates = 0;

  @override
  Future<Purchase> createPurchase(
    Purchase purchase,
    List<PurchaseItem> purchaseItems,
  ) async {
    createCalls++;
    _activeCreates++;
    if (_activeCreates > maximumConcurrentCreates) {
      maximumConcurrentCreates = _activeCreates;
    }
    try {
      if (createBarrier case final barrier?) {
        await barrier.future;
        createBarrier = null;
      }
      purchases[purchase.id] = purchase;
      items[purchase.id] = List.of(purchaseItems);
      if (failAfterCreate) {
        failAfterCreate = false;
        throw StateError('purchase write');
      }
      return purchase;
    } finally {
      _activeCreates--;
    }
  }

  @override
  Future<void> deletePurchase(String purchaseId) async {
    purchases.remove(purchaseId);
    items.remove(purchaseId);
  }

  @override
  Future<Purchase?> readPurchase(String purchaseId) async =>
      purchases[purchaseId];

  @override
  Future<List<PurchaseItem>> readPurchaseDetails(String purchaseId) async =>
      List.of(items[purchaseId] ?? const []);

  @override
  Future<List<Purchase>> readPurchaseHistory() async =>
      List.of(purchases.values);

  @override
  Future<List<Purchase>> readPurchasesByDate(DateTime date) async =>
      purchases.values
          .where((purchase) => purchase.purchaseDate == date)
          .toList();

  @override
  Future<List<Purchase>> readPurchasesByStore(String storeId) async =>
      purchases.values
          .where((purchase) => purchase.storeId == storeId)
          .toList();

  @override
  Future<Purchase> updatePurchase(
    Purchase purchase,
    List<PurchaseItem> purchaseItems,
  ) async {
    purchases[purchase.id] = purchase;
    items[purchase.id] = List.of(purchaseItems);
    return purchase;
  }
}

class _FaultPriceHistoryRepository implements PriceHistoryRepository {
  final List<PriceHistoryRecord> records = [];
  bool failAfterApply = false;

  @override
  Future<void> applyChanges({
    List<PriceHistoryRecord> added = const [],
    Set<String> removedPurchaseItemIds = const {},
  }) async {
    records.removeWhere(
      (record) => removedPurchaseItemIds.contains(record.purchaseItemId),
    );
    records.addAll(added);
    if (failAfterApply) {
      failAfterApply = false;
      throw StateError('price history write');
    }
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
    List<PriceHistoryRecord> replacement,
  ) async {
    records.removeWhere((record) => record.purchaseId == purchaseId);
    records.addAll(replacement);
  }
}
