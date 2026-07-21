import '../../services/inventory_service.dart';
import '../application/consumption_input_reader.dart';
import '../domain/consumption_event.dart';
import '../domain/consumption_snapshot.dart';

typedef ConsumptionClock = DateTime Function();

class InventoryServiceConsumptionReader implements ConsumptionInputReader {
  InventoryServiceConsumptionReader(
    this._inventoryService, {
    ConsumptionClock? clock,
  }) : _clock = clock ?? DateTime.now;

  final InventoryService _inventoryService;
  final ConsumptionClock _clock;

  @override
  Future<ConsumptionInputBatch> read() async {
    final capturedAt = _clock();
    final snapshots = <ConsumptionSnapshot>[];
    final knownProductIds = <String>{};
    for (final item in _inventoryService.items) {
      snapshots.add(
        ConsumptionSnapshot(
          productId: item.id,
          productName: item.name,
          category: item.category,
          currentQuantity: item.quantity,
          unit: item.unit,
          capturedAt: capturedAt,
        ),
      );
      knownProductIds.add(item.id);
    }

    final eventsByProduct = <String, List<ConsumptionEventInput>>{};
    for (final movement in _inventoryService.movements) {
      if (!knownProductIds.contains(movement.pantryItemId)) continue;
      eventsByProduct.putIfAbsent(movement.pantryItemId, () => []).add(
            ConsumptionEventInput(
              id: movement.id,
              productId: movement.pantryItemId,
              timestamp: movement.createdAt,
              delta: movement.amount,
              unit: movement.unit,
              movementType: movement.type,
              sourceReference: movement.note,
            ),
          );
    }
    return ConsumptionInputBatch(
      snapshots: snapshots,
      eventsByProduct: eventsByProduct,
    );
  }
}
