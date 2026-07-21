import '../../consumption/application/consumption_service.dart';
import '../../consumption/domain/consumption_result.dart';
import '../../inventory_health/application/inventory_health_service.dart';
import '../../inventory_health/domain/inventory_health_failure.dart';
import '../../inventory_health/domain/inventory_health_result.dart';
import '../domain/low_stock_failure.dart';
import '../domain/low_stock_input.dart';
import '../domain/low_stock_result.dart';
import '../engine/low_stock_engine.dart';

class LowStockService {
  const LowStockService({
    required InventoryHealthService healthService,
    required ConsumptionService consumptionService,
    LowStockEngine engine = const LowStockEngine(),
  })  : _healthService = healthService,
        _consumptionService = consumptionService,
        _engine = engine;

  final InventoryHealthService _healthService;
  final ConsumptionService _consumptionService;
  final LowStockEngine _engine;

  Future<LowStockEvaluation> evaluateInventory() async {
    final List<Object> upstream;
    try {
      upstream = await Future.wait<Object>([
        _healthService.evaluateInventory(),
        _consumptionService.evaluateInventory(),
      ]);
    } catch (_) {
      return const LowStockEvaluationFailure(
        LowStockFailure(
          code: LowStockFailureCode.inconsistentUpstreamData,
          message: 'Upstream prediction inputs could not be evaluated.',
        ),
      );
    }

    final healthEvaluation = upstream[0] as InventoryHealthEvaluation;
    final consumptionEvaluation = upstream[1] as ConsumptionEvaluation;
    return evaluateFromResults(
      healthEvaluation: healthEvaluation,
      consumptionEvaluation: consumptionEvaluation,
    );
  }

  LowStockEvaluation evaluateFromResults({
    required InventoryHealthEvaluation healthEvaluation,
    required ConsumptionEvaluation consumptionEvaluation,
  }) {
    if (healthEvaluation
        case InventoryHealthEvaluationFailure(:final failure)) {
      return LowStockEvaluationFailure(
        LowStockFailure(
          code: LowStockFailureCode.upstreamHealthFailure,
          message: failure.message,
        ),
      );
    }
    if (consumptionEvaluation
        case ConsumptionEvaluationFailure(:final failure)) {
      return LowStockEvaluationFailure(
        LowStockFailure(
          code: LowStockFailureCode.upstreamConsumptionFailure,
          message: failure.message,
        ),
      );
    }

    final healthResults =
        (healthEvaluation as InventoryHealthEvaluationSuccess).results;
    final consumptionSuccess =
        consumptionEvaluation as ConsumptionEvaluationSuccess;
    final healthById = <String, InventoryHealthResult>{};
    for (final result in healthResults) {
      if (healthById.containsKey(result.productId)) {
        return const LowStockEvaluationFailure(
          LowStockFailure(
            code: LowStockFailureCode.duplicateProductId,
            message: 'Health results contain duplicate product identifiers.',
          ),
        );
      }
      healthById[result.productId] = result;
    }
    final consumptionById = <String, ConsumptionResult>{};
    for (final result in consumptionSuccess.results) {
      final productId = result.snapshot.productId;
      if (consumptionById.containsKey(productId) ||
          consumptionSuccess.failures.containsKey(productId)) {
        return const LowStockEvaluationFailure(
          LowStockFailure(
            code: LowStockFailureCode.duplicateProductId,
            message:
                'Consumption results contain ambiguous product identifiers.',
          ),
        );
      }
      consumptionById[productId] = result;
    }

    final results = <LowStockResult>[];
    final failures = <String, LowStockFailure>{};
    for (final health in healthResults) {
      final productId = health.productId;
      final consumptionFailure = consumptionSuccess.failures[productId];
      if (consumptionFailure != null) {
        failures[productId] = LowStockFailure(
          code: LowStockFailureCode.upstreamConsumptionFailure,
          message: consumptionFailure.message,
          productId: productId,
        );
        continue;
      }
      final consumption = consumptionById[productId];
      if (consumption == null) {
        failures[productId] = LowStockFailure(
          code: LowStockFailureCode.missingPairedResult,
          message: 'The product has no paired Consumption result.',
          productId: productId,
        );
        continue;
      }
      try {
        final evaluation = _engine.evaluate(
          LowStockInput(
            healthResult: health,
            consumptionResult: consumption,
          ),
        );
        switch (evaluation) {
          case LowStockItemSuccess(:final result):
            results.add(result);
          case LowStockItemFailure(:final failure):
            failures[productId] = failure;
        }
      } catch (_) {
        failures[productId] = LowStockFailure(
          code: LowStockFailureCode.evaluationFailed,
          message: 'The product could not be evaluated.',
          productId: productId,
        );
      }
    }

    for (final productId in consumptionById.keys) {
      if (!healthById.containsKey(productId)) {
        failures[productId] = LowStockFailure(
          code: LowStockFailureCode.missingPairedResult,
          message: 'The product has no paired Health result.',
          productId: productId,
        );
      }
    }
    for (final entry in consumptionSuccess.failures.entries) {
      if (!healthById.containsKey(entry.key)) {
        failures[entry.key] = LowStockFailure(
          code: LowStockFailureCode.missingPairedResult,
          message: 'The failed Consumption result has no paired Health result.',
          productId: entry.key,
        );
      }
    }
    return LowStockEvaluationSuccess(results: results, failures: failures);
  }
}
