enum ConsumptionFailureCode {
  inputUnavailable,
  productNotFound,
  invalidSnapshot,
  invalidEvent,
  duplicateProductId,
  duplicateEvent,
  missingTimestamp,
  outOfOrderHistory,
  unitMismatch,
  inconsistentHistory,
  evaluationFailed,
}

class ConsumptionFailure {
  const ConsumptionFailure({
    required this.code,
    required this.message,
    this.productId,
  });

  final ConsumptionFailureCode code;
  final String message;
  final String? productId;
}
