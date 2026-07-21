import '../../consumption/application/consumption_service.dart';
import '../../consumption/domain/consumption_result.dart';
import '../../inventory_health/application/inventory_health_service.dart';
import '../../inventory_health/domain/inventory_health_failure.dart';
import '../../inventory_health/domain/inventory_health_result.dart';
import '../../low_stock/application/low_stock_service.dart';
import '../../low_stock/domain/low_stock_result.dart';
import '../domain/shopping_recommendation.dart';
import '../domain/shopping_recommendation_failure.dart';
import '../domain/shopping_recommendation_input.dart';
import '../domain/shopping_recommendation_result.dart';
import '../engine/shopping_recommendation_engine.dart';

class ShoppingRecommendationService {
  const ShoppingRecommendationService({
    required InventoryHealthService healthService,
    required ConsumptionService consumptionService,
    required LowStockService lowStockService,
    ShoppingRecommendationEngine engine = const ShoppingRecommendationEngine(),
  })  : _healthService = healthService,
        _consumptionService = consumptionService,
        _lowStockService = lowStockService,
        _engine = engine;

  final InventoryHealthService _healthService;
  final ConsumptionService _consumptionService;
  final LowStockService _lowStockService;
  final ShoppingRecommendationEngine _engine;

  Future<ShoppingRecommendationEvaluation> evaluateInventory() async {
    final List<Object> upstream;
    try {
      upstream = await Future.wait<Object>([
        _healthService.evaluateInventory(),
        _consumptionService.evaluateInventory(),
      ]);
    } catch (_) {
      return const ShoppingRecommendationEvaluationFailure(
        ShoppingRecommendationFailure(
          code: ShoppingRecommendationFailureCode.inconsistentUpstreamData,
          message: 'Recommendation inputs could not be evaluated.',
        ),
      );
    }

    final healthEvaluation = upstream[0] as InventoryHealthEvaluation;
    final consumptionEvaluation = upstream[1] as ConsumptionEvaluation;
    if (healthEvaluation
        case InventoryHealthEvaluationFailure(:final failure)) {
      return ShoppingRecommendationEvaluationFailure(
        ShoppingRecommendationFailure(
          code: ShoppingRecommendationFailureCode.upstreamHealthFailure,
          message: failure.message,
        ),
      );
    }
    if (consumptionEvaluation
        case ConsumptionEvaluationFailure(:final failure)) {
      return ShoppingRecommendationEvaluationFailure(
        ShoppingRecommendationFailure(
          code: ShoppingRecommendationFailureCode.upstreamConsumptionFailure,
          message: failure.message,
        ),
      );
    }

    final lowStockEvaluation = _lowStockService.evaluateFromResults(
      healthEvaluation: healthEvaluation,
      consumptionEvaluation: consumptionEvaluation,
    );
    if (lowStockEvaluation case LowStockEvaluationFailure(:final failure)) {
      return ShoppingRecommendationEvaluationFailure(
        ShoppingRecommendationFailure(
          code: ShoppingRecommendationFailureCode.upstreamLowStockFailure,
          message: failure.message,
        ),
      );
    }

    final healthResults =
        (healthEvaluation as InventoryHealthEvaluationSuccess).results;
    final consumptionSuccess =
        consumptionEvaluation as ConsumptionEvaluationSuccess;
    final lowStockSuccess = lowStockEvaluation as LowStockEvaluationSuccess;
    final healthById = <String, InventoryHealthResult>{};
    for (final result in healthResults) {
      if (healthById.containsKey(result.productId)) {
        return _duplicateFailure('Health');
      }
      healthById[result.productId] = result;
    }
    final consumptionById = <String, ConsumptionResult>{};
    for (final result in consumptionSuccess.results) {
      final productId = result.snapshot.productId;
      if (consumptionById.containsKey(productId) ||
          consumptionSuccess.failures.containsKey(productId)) {
        return _duplicateFailure('Consumption');
      }
      consumptionById[productId] = result;
    }
    final lowStockById = <String, LowStockResult>{};
    for (final result in lowStockSuccess.results) {
      if (lowStockById.containsKey(result.productId) ||
          lowStockSuccess.failures.containsKey(result.productId)) {
        return _duplicateFailure('Low Stock');
      }
      lowStockById[result.productId] = result;
    }

    final results = <ShoppingRecommendationResult>[];
    final failures = <String, ShoppingRecommendationFailure>{};
    for (final health in healthResults) {
      final productId = health.productId;
      final consumptionFailure = consumptionSuccess.failures[productId];
      if (consumptionFailure != null) {
        failures[productId] = ShoppingRecommendationFailure(
          code: ShoppingRecommendationFailureCode.upstreamConsumptionFailure,
          message: consumptionFailure.message,
          productId: productId,
        );
        continue;
      }
      final lowStockFailure = lowStockSuccess.failures[productId];
      if (lowStockFailure != null) {
        failures[productId] = ShoppingRecommendationFailure(
          code: ShoppingRecommendationFailureCode.upstreamLowStockFailure,
          message: lowStockFailure.message,
          productId: productId,
        );
        continue;
      }
      final consumption = consumptionById[productId];
      final lowStock = lowStockById[productId];
      if (consumption == null || lowStock == null) {
        failures[productId] = _missingFailure(productId);
        continue;
      }
      try {
        final evaluation = _engine.evaluate(
          ShoppingRecommendationInput(
            healthResult: health,
            consumptionResult: consumption,
            lowStockResult: lowStock,
          ),
        );
        switch (evaluation) {
          case ShoppingRecommendationItemSuccess(:final result):
            results.add(result);
          case ShoppingRecommendationItemFailure(:final failure):
            failures[productId] = failure;
        }
      } catch (_) {
        failures[productId] = ShoppingRecommendationFailure(
          code: ShoppingRecommendationFailureCode.evaluationFailed,
          message: 'The product recommendation could not be evaluated.',
          productId: productId,
        );
      }
    }

    final otherIds = <String>{
      ...consumptionById.keys,
      ...consumptionSuccess.failures.keys,
      ...lowStockById.keys,
      ...lowStockSuccess.failures.keys,
    };
    for (final productId in otherIds) {
      if (!healthById.containsKey(productId)) {
        failures[productId] = _missingFailure(productId);
      }
    }
    results.sort(_compareResults);
    return ShoppingRecommendationEvaluationSuccess(
      results: results,
      failures: failures,
    );
  }

  ShoppingRecommendationEvaluationFailure _duplicateFailure(String source) =>
      ShoppingRecommendationEvaluationFailure(
        ShoppingRecommendationFailure(
          code: ShoppingRecommendationFailureCode.duplicateProductId,
          message: '$source results contain duplicate product identifiers.',
        ),
      );

  ShoppingRecommendationFailure _missingFailure(String productId) =>
      ShoppingRecommendationFailure(
        code: ShoppingRecommendationFailureCode.missingPairedResult,
        message: 'The product does not have all three required Results.',
        productId: productId,
      );

  static int _compareResults(
    ShoppingRecommendationResult left,
    ShoppingRecommendationResult right,
  ) {
    final priority = _priority(left.recommendation.state)
        .compareTo(_priority(right.recommendation.state));
    if (priority != 0) return priority;
    final name = left.productName.toLowerCase().compareTo(
          right.productName.toLowerCase(),
        );
    return name != 0 ? name : left.productId.compareTo(right.productId);
  }

  static int _priority(ShoppingRecommendationState state) => switch (state) {
        ShoppingRecommendationState.buyNow => 0,
        ShoppingRecommendationState.buySoon => 1,
        ShoppingRecommendationState.watch => 2,
        ShoppingRecommendationState.ignore => 3,
      };
}
