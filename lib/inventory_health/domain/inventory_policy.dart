class InventoryPolicy {
  const InventoryPolicy({
    required this.productId,
    required this.lowStockThreshold,
    required this.unit,
  });

  final String productId;
  final double lowStockThreshold;
  final String unit;
}
