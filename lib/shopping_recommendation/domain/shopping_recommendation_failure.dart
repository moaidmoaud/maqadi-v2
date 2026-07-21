enum ShoppingRecommendationFailureCode {
  upstreamHealthFailure,
  upstreamConsumptionFailure,
  upstreamLowStockFailure,
  duplicateProductId,
  missingPairedResult,
  productIdMismatch,
  unitMismatch,
  invalidNumericInput,
  quantityMismatch,
  invalidConsumptionEvidence,
  inconsistentHealthEvidence,
  inconsistentLowStockEvidence,
  unsupportedCombination,
  inconsistentUpstreamData,
  evaluationFailed,
}

class ShoppingRecommendationFailure {
  const ShoppingRecommendationFailure({
    required this.code,
    required this.message,
    this.productId,
  });

  final ShoppingRecommendationFailureCode code;
  final String message;
  final String? productId;
}
