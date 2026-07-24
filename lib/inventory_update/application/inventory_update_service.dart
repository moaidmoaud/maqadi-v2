import '../../services/inventory_service.dart';
import '../domain/inventory_update_models.dart';
import '../engine/inventory_update_engine.dart';

class InventoryUpdateService {
  const InventoryUpdateService({
    required InventoryService inventoryService,
    InventoryUpdateEngine engine = const InventoryUpdateEngine(),
    this.defaultCategory = 'أخرى',
    this.defaultMinimum = 1,
    this.defaultUnit = 'حبة',
    this.defaultLocation = 'المخزن',
  })  : _inventoryService = inventoryService,
        _engine = engine;

  final InventoryService _inventoryService;
  final InventoryUpdateEngine _engine;
  final String defaultCategory;
  final double defaultMinimum;
  final String defaultUnit;
  final String defaultLocation;

  Future<InventoryUpdatePlan> createPlan(InventoryUpdateInput input) async =>
      _engine.createPlan(
        input: input,
        inventory: [
          for (final item in _inventoryService.items)
            InventoryProductSnapshot(
              productId: item.id,
              displayName: item.name,
              quantity: item.quantity,
            ),
        ],
        processedSourceKeys: _processedSourceKeys(),
      );

  Future<InventoryUpdateResult> apply(InventoryUpdateInput input) async {
    final plan = await createPlan(input);
    final added = <String>[];
    final updated = <String>[];
    final ignored = <String>[];
    final unknown = <String>[];

    for (final action in plan.actions) {
      final note = inventoryUpdateSourceKey(
        input.receiptId,
        action.receiptLineId,
      );
      switch (action.type) {
        case InventoryUpdateActionType.addNewProduct:
          final item = _inventoryService.addStock(
            name: action.productName,
            category: defaultCategory,
            quantity: action.trace.receiptQuantity,
            minimum: defaultMinimum,
            unit: defaultUnit,
            location: defaultLocation,
            movementType: 'شراء',
            note: note,
            receivedAt: input.receivedAt,
            updateExistingDetails: false,
          );
          added.add(item.id);
        case InventoryUpdateActionType.increaseQuantity:
          final item = _inventoryService.findByName(action.productName);
          if (item == null) {
            throw StateError(
              'Inventory changed after planning: ${action.productName}',
            );
          }
          _inventoryService.addBatch(
            item,
            quantity: action.trace.receiptQuantity,
            receivedAt: input.receivedAt,
            note: note,
            movementType: 'شراء',
          );
          updated.add(item.id);
        case InventoryUpdateActionType.ignoreDuplicate:
          ignored.add(action.receiptLineId);
        case InventoryUpdateActionType.unknownProduct:
          unknown.add(action.receiptLineId);
      }
    }

    return InventoryUpdateResult(
      plan: plan,
      productsAdded: added,
      productsUpdated: updated,
      productsIgnored: ignored,
      unknownProducts: unknown,
    );
  }

  Set<String> _processedSourceKeys() => _inventoryService.movements
      .map((movement) => movement.note)
      .whereType<String>()
      .where((note) => note.startsWith('inventory-update|'))
      .toSet();
}
