import '../../consumption/domain/consumption_result.dart';
import '../../inventory_health/domain/inventory_health_result.dart';
import '../../low_stock/domain/low_stock_result.dart';

class ShoppingRecommendationInput {
  const ShoppingRecommendationInput({
    required this.healthResult,
    required this.consumptionResult,
    required this.lowStockResult,
  });

  final InventoryHealthResult healthResult;
  final ConsumptionResult consumptionResult;
  final LowStockResult lowStockResult;
}
