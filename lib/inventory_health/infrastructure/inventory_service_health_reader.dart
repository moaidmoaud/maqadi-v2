import '../../services/inventory_service.dart';
import '../application/inventory_health_input_reader.dart';
import '../domain/inventory_health_snapshot.dart';
import '../domain/inventory_policy.dart';

class InventoryServiceHealthReader implements InventoryHealthInputReader {
  const InventoryServiceHealthReader(this._inventoryService);

  final InventoryService _inventoryService;

  @override
  Future<InventoryHealthInputBatch> read() async {
    final snapshots = <InventoryHealthSnapshot>[];
    final policies = <InventoryPolicy>[];
    for (final item in _inventoryService.items) {
      snapshots.add(
        InventoryHealthSnapshot(
          productId: item.id,
          productName: item.name,
          category: item.category,
          quantity: item.quantity,
          unit: item.unit,
        ),
      );
      policies.add(
        InventoryPolicy(
          productId: item.id,
          lowStockThreshold: item.minimum,
          unit: item.unit,
        ),
      );
    }
    return InventoryHealthInputBatch(
      snapshots: snapshots,
      policies: policies,
    );
  }
}
