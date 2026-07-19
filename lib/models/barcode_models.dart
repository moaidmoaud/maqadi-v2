import 'inventory_models.dart';

class InventoryQrTarget {
  const InventoryQrTarget({required this.item, this.batch});

  final PantryItem item;
  final InventoryBatch? batch;
}

enum InventoryScanResultType { internalQr, barcode, unknown }

class InventoryScanResult {
  const InventoryScanResult({
    required this.type,
    required this.rawValue,
    this.item,
    this.batch,
  });

  final InventoryScanResultType type;
  final String rawValue;
  final PantryItem? item;
  final InventoryBatch? batch;
}
