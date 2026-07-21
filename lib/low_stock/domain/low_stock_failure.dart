enum LowStockFailureCode {
  upstreamHealthFailure,
  upstreamConsumptionFailure,
  duplicateProductId,
  missingPairedResult,
  productIdMismatch,
  unitMismatch,
  quantityMismatch,
  invalidNumericInput,
  invalidThreshold,
  invalidObservationPeriod,
  invalidConsumptionProfile,
  inconsistentUpstreamData,
  evaluationFailed,
}

class LowStockFailure {
  const LowStockFailure({
    required this.code,
    required this.message,
    this.productId,
  });

  final LowStockFailureCode code;
  final String message;
  final String? productId;
}
