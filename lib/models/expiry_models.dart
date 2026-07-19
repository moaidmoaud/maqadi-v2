import 'inventory_models.dart';

enum BatchExpiryStatus { fresh, expiringSoon, expired }

class BatchExpiryInfo {
  const BatchExpiryInfo({
    required this.item,
    required this.batch,
    required this.status,
    required this.daysRemaining,
  });

  final PantryItem item;
  final InventoryBatch batch;
  final BatchExpiryStatus status;
  final int? daysRemaining;
}
