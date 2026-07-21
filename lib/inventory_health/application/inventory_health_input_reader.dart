import '../domain/inventory_health_snapshot.dart';
import '../domain/inventory_policy.dart';

class InventoryHealthInputBatch {
  InventoryHealthInputBatch({
    required Iterable<InventoryHealthSnapshot> snapshots,
    required Iterable<InventoryPolicy> policies,
  })  : snapshots = List.unmodifiable(snapshots),
        policies = List.unmodifiable(policies);

  final List<InventoryHealthSnapshot> snapshots;
  final List<InventoryPolicy> policies;
}

abstract interface class InventoryHealthInputReader {
  Future<InventoryHealthInputBatch> read();
}
