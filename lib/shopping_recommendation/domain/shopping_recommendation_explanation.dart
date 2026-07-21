import '../../consumption/domain/consumption_profile.dart';
import '../../inventory_health/domain/inventory_health_result.dart';
import '../../low_stock/domain/low_stock_prediction.dart';
import 'shopping_recommendation.dart';

enum ShoppingRecommendationReasonCode {
  alreadyOutOfStock,
  alreadyLowStock,
  projectedLowSoon,
  monitoringRecommended,
  healthyNoAction,
  insufficientHealthEvidence,
}

class ShoppingRecommendationExplanation {
  const ShoppingRecommendationExplanation({
    required this.recommendation,
    required this.reasonCode,
    required this.healthState,
    required this.consumptionPattern,
    required this.consumptionSummary,
    required this.lowStockPrediction,
    required this.evidence,
    this.summary,
  });

  final ShoppingRecommendationState recommendation;
  final ShoppingRecommendationReasonCode reasonCode;
  final InventoryHealthStatus healthState;
  final ConsumptionPattern consumptionPattern;
  final String? consumptionSummary;
  final LowStockPredictionState lowStockPrediction;
  final ShoppingRecommendation evidence;
  final String? summary;
}
