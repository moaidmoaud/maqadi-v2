import 'package:maqadi_v2/consumption/domain/consumption_result.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_result.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_prediction.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_input.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_result.dart';
import 'package:maqadi_v2/low_stock/engine/low_stock_engine.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_input.dart';

import 'low_stock_test_support.dart';

export 'low_stock_test_support.dart';

LowStockResult lowStockResultFor(
  InventoryHealthResult health,
  ConsumptionResult consumption,
) {
  final evaluation = const LowStockEngine().evaluate(
    LowStockInput(
      healthResult: health,
      consumptionResult: consumption,
    ),
  );
  return (evaluation as LowStockItemSuccess).result;
}

ShoppingRecommendationInput recommendationInput({
  InventoryHealthResult? health,
  ConsumptionResult? consumption,
  LowStockResult? lowStock,
}) {
  final resolvedHealth = health ?? healthResult();
  final resolvedConsumption = consumption ?? consumptionResult();
  return ShoppingRecommendationInput(
    healthResult: resolvedHealth,
    consumptionResult: resolvedConsumption,
    lowStockResult:
        lowStock ?? lowStockResultFor(resolvedHealth, resolvedConsumption),
  );
}

ShoppingRecommendationInput inputForStatus(
  InventoryHealthStatus status, {
  String id = 'rice',
}) {
  final quantity = switch (status) {
    InventoryHealthStatus.outOfStock => 0.0,
    InventoryHealthStatus.lowStock => 2.0,
    _ => 10.0,
  };
  final threshold = status == InventoryHealthStatus.unknown ? null : 2.0;
  final health = healthResult(
    id: id,
    status: status,
    quantity: quantity,
    threshold: threshold,
  );
  final consumption = consumptionResult(
    id: id,
    quantity: quantity,
    totalConsumed: 9,
  );
  return recommendationInput(health: health, consumption: consumption);
}

LowStockResult replaceLowStock(
  LowStockResult source, {
  String? productId,
  LowStockPrediction? prediction,
  LowStockExplanation? explanation,
}) =>
    LowStockResult(
      productId: productId ?? source.productId,
      productName: source.productName,
      category: source.category,
      prediction: prediction ?? source.prediction,
      explanation: explanation ?? source.explanation,
    );

LowStockPrediction replacePrediction(
  LowStockPrediction source, {
  LowStockPredictionState? state,
  double? currentQuantity,
  double? totalObservedConsumption,
}) =>
    LowStockPrediction(
      state: state ?? source.state,
      currentQuantity: currentQuantity ?? source.currentQuantity,
      lowStockThreshold: source.lowStockThreshold,
      totalObservedConsumption:
          totalObservedConsumption ?? source.totalObservedConsumption,
      consumptionEventCount: source.consumptionEventCount,
      observationDurationDays: source.observationDurationDays,
      dailyConsumption: source.dailyConsumption,
      projectedQuantity: source.projectedQuantity,
      predictionHorizonDays: source.predictionHorizonDays,
    );
