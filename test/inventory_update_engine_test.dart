import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/inventory_update/application/inventory_update_service.dart';
import 'package:maqadi_v2/inventory_update/domain/inventory_update_models.dart';
import 'package:maqadi_v2/inventory_update/engine/inventory_update_engine.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

import 'inventory_update_test_support.dart';

void main() {
  test('adds a newly matched catalog product to inventory', () async {
    var id = 0;
    final inventory = InventoryService(idFactory: () => 'id-${++id}');
    final service = InventoryUpdateService(inventoryService: inventory);
    final input = updateInput([
      receiptProduct(
        finalMatch(
          lineId: 'line-garlic',
          productId: 'catalog-garlic',
          displayName: 'ثوم',
        ),
        quantity: 2,
      ),
    ]);

    final result = await service.apply(input);

    expect(result.productsAdded, ['id-1']);
    expect(result.productsUpdated, isEmpty);
    expect(inventory.items.single.name, 'ثوم');
    expect(inventory.items.single.quantity, 2);
    expect(result.plan.actions.single.type,
        InventoryUpdateActionType.addNewProduct);
    expect(result.plan.actions.single.trace.previousInventory, isNull);
    expect(result.plan.actions.single.trace.receiptQuantity, 2);
    expect(result.plan.actions.single.trace.newQuantity, 2);
  });

  test('increases an existing product through InventoryService', () async {
    var id = 0;
    final inventory = InventoryService(idFactory: () => 'id-${++id}');
    final existing = inventory.addStock(
      name: 'ثوم',
      category: 'الخضار',
      quantity: 3,
      minimum: 1,
      unit: 'حبة',
      location: 'المخزن',
    );
    final service = InventoryUpdateService(inventoryService: inventory);
    final input = updateInput([
      receiptProduct(
        finalMatch(
          lineId: 'line-garlic',
          productId: 'catalog-garlic',
          displayName: 'ثوم',
        ),
        quantity: 2,
      ),
    ]);

    final result = await service.apply(input);

    expect(result.productsAdded, isEmpty);
    expect(result.productsUpdated, [existing.id]);
    expect(existing.quantity, 5);
    final action = result.plan.actions.single;
    expect(action.type, InventoryUpdateActionType.increaseQuantity);
    expect(action.trace.previousInventory?.quantity, 3);
    expect(action.trace.receiptQuantity, 2);
    expect(action.trace.newQuantity, 5);
  });

  test('reapplying the same receipt line ignores the duplicate', () async {
    final inventory = InventoryService();
    final service = InventoryUpdateService(inventoryService: inventory);
    final input = updateInput([
      receiptProduct(
        finalMatch(
          lineId: 'line-garlic',
          productId: 'catalog-garlic',
          displayName: 'ثوم',
        ),
        quantity: 2,
      ),
    ]);

    await service.apply(input);
    final second = await service.apply(input);

    expect(inventory.items.single.quantity, 2);
    expect(second.productsIgnored, ['line-garlic']);
    expect(second.productsAdded, isEmpty);
    expect(second.productsUpdated, isEmpty);
    expect(
      second.plan.actions.single.type,
      InventoryUpdateActionType.ignoreDuplicate,
    );
    expect(
      second.plan.actions.single.trace.reason,
      InventoryUpdateReason.duplicateReceiptLine,
    );
  });

  test('keeps an unmatched receipt line as an unknown product', () async {
    final inventory = InventoryService();
    final service = InventoryUpdateService(inventoryService: inventory);
    final input = updateInput([
      receiptProduct(unknownMatch(lineId: 'line-unknown')),
    ]);

    final result = await service.apply(input);

    expect(inventory.items, isEmpty);
    expect(result.unknownProducts, ['line-unknown']);
    expect(
      result.plan.actions.single.type,
      InventoryUpdateActionType.unknownProduct,
    );
    expect(
      result.plan.actions.single.trace.reason,
      InventoryUpdateReason.productNotMatched,
    );
  });

  test('plan and result serialize without losing trace evidence', () async {
    const engine = InventoryUpdateEngine();
    final input = updateInput([
      receiptProduct(
        finalMatch(
          lineId: 'line-garlic',
          productId: 'catalog-garlic',
          displayName: 'ثوم',
        ),
        quantity: 2,
      ),
    ]);
    final plan = engine.createPlan(
      input: input,
      inventory: const [
        InventoryProductSnapshot(
          productId: 'inventory-garlic',
          displayName: 'ثوم',
          quantity: 3,
        ),
      ],
    );
    final result = InventoryUpdateResult(
      plan: plan,
      productsAdded: const [],
      productsUpdated: const ['inventory-garlic'],
      productsIgnored: const [],
      unknownProducts: const [],
    );

    expect(
      InventoryUpdateInput.fromJson(input.toJson()).toJson(),
      input.toJson(),
    );
    expect(
      InventoryUpdatePlan.fromJson(plan.toJson()).toJson(),
      plan.toJson(),
    );
    expect(
      InventoryUpdateResult.fromJson(result.toJson()).toJson(),
      result.toJson(),
    );
  });

  test('creates one deterministic action for every receipt product', () {
    const engine = InventoryUpdateEngine();
    final matched = finalMatch(
      lineId: 'line-1',
      productId: 'catalog-garlic',
      displayName: 'ثوم',
    );
    final input = updateInput([
      receiptProduct(matched),
      receiptProduct(matched),
      receiptProduct(unknownMatch(lineId: 'line-2')),
    ]);

    final plan = engine.createPlan(input: input, inventory: const []);

    expect(plan.actions, hasLength(3));
    expect(plan.productsAdded, 1);
    expect(plan.productsIgnored, 1);
    expect(plan.unknownProducts, 1);
  });
}
