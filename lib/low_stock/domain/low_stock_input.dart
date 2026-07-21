import '../../consumption/domain/consumption_result.dart';
import '../../inventory_health/domain/inventory_health_result.dart';

class LowStockInput {
  const LowStockInput({
    required this.healthResult,
    required this.consumptionResult,
  });

  final InventoryHealthResult healthResult;
  final ConsumptionResult consumptionResult;
}
