enum InventoryHealthStatus { unknown, healthy, lowStock, outOfStock }

enum InventoryHealthReasonCode {
  invalidSnapshot,
  invalidQuantity,
  negativeQuantity,
  quantityIsZero,
  missingPolicy,
  invalidPolicy,
  invalidThreshold,
  unitMismatch,
  quantityAtOrBelowThreshold,
  quantityAboveThreshold,
}

class InventoryHealthExplanation {
  const InventoryHealthExplanation({
    required this.status,
    required this.reasonCode,
    required this.quantity,
    required this.threshold,
    required this.unit,
    required this.timestamp,
    this.summary,
  });

  final InventoryHealthStatus status;
  final InventoryHealthReasonCode reasonCode;
  final double quantity;
  final double? threshold;
  final String unit;
  final DateTime timestamp;
  final String? summary;
}

class InventoryHealthResult {
  const InventoryHealthResult({
    required this.productId,
    required this.productName,
    required this.category,
    required this.explanation,
  });

  final String productId;
  final String productName;
  final String category;
  final InventoryHealthExplanation explanation;

  InventoryHealthStatus get status => explanation.status;
}
