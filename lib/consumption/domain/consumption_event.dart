enum ConsumptionReason {
  consumption,
  purchase,
  stockAddition,
  manualAdjustment,
  batchAdjustment,
  batchRemoval,
  unknown,
}

enum ConsumptionSource { inventory, purchase, batch, manual, unknown }

class ConsumptionEventInput {
  const ConsumptionEventInput({
    required this.id,
    required this.productId,
    required this.timestamp,
    required this.delta,
    required this.unit,
    required this.movementType,
    this.sourceReference,
  });

  final String id;
  final String productId;
  final DateTime? timestamp;
  final double delta;
  final String unit;
  final String movementType;
  final String? sourceReference;
}

class ConsumptionEvent {
  const ConsumptionEvent({
    required this.id,
    required this.productId,
    required this.timestamp,
    required this.previousQuantity,
    required this.currentQuantity,
    required this.delta,
    required this.reason,
    required this.source,
    required this.unit,
    this.sourceReference,
  });

  final String id;
  final String productId;
  final DateTime timestamp;
  final double previousQuantity;
  final double currentQuantity;
  final double delta;
  final ConsumptionReason reason;
  final ConsumptionSource source;
  final String unit;
  final String? sourceReference;
}
