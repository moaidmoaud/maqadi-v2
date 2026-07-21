class ConsumptionSnapshot {
  const ConsumptionSnapshot({
    required this.productId,
    required this.productName,
    required this.category,
    required this.currentQuantity,
    required this.unit,
    required this.capturedAt,
  });

  final String productId;
  final String productName;
  final String category;
  final double currentQuantity;
  final String unit;
  final DateTime capturedAt;
}
