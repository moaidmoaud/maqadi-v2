class InventoryHealthSnapshot {
  const InventoryHealthSnapshot({
    required this.productId,
    required this.productName,
    required this.category,
    required this.quantity,
    required this.unit,
  });

  final String productId;
  final String productName;
  final String category;
  final double quantity;
  final String unit;
}
