import 'package:maqadi_v2/inventory_update/application/inventory_update_service.dart';
import 'package:maqadi_v2/inventory_update/domain/inventory_update_models.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/receipt_commit/application/receipt_commit_service.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

import 'inventory_update_test_support.dart';

class ReceiptCommitHarness {
  ReceiptCommitHarness({List<PantryItem>? items})
      : inventory = InventoryService(items: items),
        _clock = _TestClock() {
    updateService = InventoryUpdateService(inventoryService: inventory);
    service = ReceiptCommitService(
      inventoryUpdateService: updateService,
      clock: _clock.call,
      idFactory: _nextId,
    );
  }

  final InventoryService inventory;
  final _TestClock _clock;
  late final InventoryUpdateService updateService;
  late final ReceiptCommitService service;
  int _id = 0;

  String _nextId() => 'commit-${++_id}';
}

class _TestClock {
  int _second = 0;

  DateTime call() => DateTime.utc(2026, 7, 24, 9, 0, _second++);
}

InventoryUpdateInput mixedCommitInput() {
  final potato = finalMatch(
    lineId: 'line-potato',
    productId: 'catalog-potato',
    displayName: 'بطاطس',
  );
  return updateInput([
    receiptProduct(
      finalMatch(
        lineId: 'line-garlic',
        productId: 'catalog-garlic',
        displayName: 'ثوم',
      ),
      quantity: 2,
    ),
    receiptProduct(potato, quantity: 1),
    receiptProduct(potato, quantity: 1),
    receiptProduct(unknownMatch(lineId: 'line-unknown')),
  ]);
}

PantryItem garlicInventory({double quantity = 3}) => PantryItem(
      id: 'inventory-garlic',
      name: 'ثوم',
      category: 'الخضار',
      minimum: 1,
      unit: 'حبة',
      location: 'المخزن',
      quantity: quantity,
    );
