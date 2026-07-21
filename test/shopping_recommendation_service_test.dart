import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/consumption/application/consumption_input_reader.dart';
import 'package:maqadi_v2/consumption/application/consumption_service.dart';
import 'package:maqadi_v2/consumption/domain/consumption_failure.dart';
import 'package:maqadi_v2/consumption/domain/consumption_result.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_input_reader.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_service.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_failure.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_result.dart';
import 'package:maqadi_v2/low_stock/application/low_stock_service.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_failure.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_result.dart';
import 'package:maqadi_v2/shopping_recommendation/application/shopping_recommendation_service.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_failure.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_input.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_result.dart';
import 'package:maqadi_v2/shopping_recommendation/engine/shopping_recommendation_engine.dart';

import 'shopping_recommendation_test_support.dart';

void main() {
  InventoryHealthEvaluationSuccess healthSuccess(
    Iterable<InventoryHealthResult> results,
  ) =>
      InventoryHealthEvaluationSuccess(List.unmodifiable(results));

  ConsumptionEvaluationSuccess consumptionSuccess(
    Iterable<ConsumptionResult> results, {
    Map<String, ConsumptionFailure> failures = const {},
  }) =>
      ConsumptionEvaluationSuccess(results: results, failures: failures);

  LowStockEvaluationSuccess lowStockSuccess(
    Iterable<LowStockResult> results, {
    Map<String, LowStockFailure> failures = const {},
  }) =>
      LowStockEvaluationSuccess(results: results, failures: failures);

  ShoppingRecommendationService service({
    required InventoryHealthEvaluation health,
    required ConsumptionEvaluation consumption,
    required LowStockEvaluation lowStock,
    ShoppingRecommendationEngine engine = const ShoppingRecommendationEngine(),
  }) =>
      ShoppingRecommendationService(
        healthService: _HealthService(health),
        consumptionService: _ConsumptionService(consumption),
        lowStockService: _LowStockService(lowStock),
        engine: engine,
      );

  test('evaluates upstream batches once and every valid triple once', () async {
    final first = recommendationInput();
    final second = inputForStatus(InventoryHealthStatus.outOfStock, id: 'salt');
    final healthEvaluation = healthSuccess([
      first.healthResult,
      second.healthResult,
    ]);
    final consumptionEvaluation = consumptionSuccess([
      first.consumptionResult,
      second.consumptionResult,
    ]);
    final health = _HealthService(healthEvaluation);
    final consumption = _ConsumptionService(consumptionEvaluation);
    final lowStock = _LowStockService(lowStockSuccess([
      first.lowStockResult,
      second.lowStockResult,
    ]));
    final engine = _CountingEngine();
    final result = await ShoppingRecommendationService(
      healthService: health,
      consumptionService: consumption,
      lowStockService: lowStock,
      engine: engine,
    ).evaluateInventory() as ShoppingRecommendationEvaluationSuccess;

    expect((health.calls, consumption.calls, lowStock.calls, engine.calls),
        (1, 1, 1, 2));
    expect(lowStock.receivedHealth, same(healthEvaluation));
    expect(lowStock.receivedConsumption, same(consumptionEvaluation));
    expect(result.results.first.recommendation.state,
        ShoppingRecommendationState.buyNow);
  });

  test('maps a complete Health failure', () async {
    final result = await service(
      health: const InventoryHealthEvaluationFailure(
        InventoryHealthFailure(
          code: InventoryHealthFailureCode.inputUnavailable,
          message: 'health unavailable',
        ),
      ),
      consumption: consumptionSuccess(const []),
      lowStock: lowStockSuccess(const []),
    ).evaluateInventory() as ShoppingRecommendationEvaluationFailure;
    expect(result.failure.code,
        ShoppingRecommendationFailureCode.upstreamHealthFailure);
  });

  test('maps a complete Consumption failure', () async {
    final result = await service(
      health: healthSuccess(const []),
      consumption: const ConsumptionEvaluationFailure(
        ConsumptionFailure(
          code: ConsumptionFailureCode.inputUnavailable,
          message: 'consumption unavailable',
        ),
      ),
      lowStock: lowStockSuccess(const []),
    ).evaluateInventory() as ShoppingRecommendationEvaluationFailure;
    expect(result.failure.code,
        ShoppingRecommendationFailureCode.upstreamConsumptionFailure);
  });

  test('maps an unexpected upstream exception', () async {
    final result = await ShoppingRecommendationService(
      healthService: _ThrowingHealthService(),
      consumptionService: _ConsumptionService(consumptionSuccess(const [])),
      lowStockService: _LowStockService(lowStockSuccess(const [])),
    ).evaluateInventory() as ShoppingRecommendationEvaluationFailure;
    expect(result.failure.code,
        ShoppingRecommendationFailureCode.inconsistentUpstreamData);
  });

  test('maps a complete Low Stock failure', () async {
    final result = await service(
      health: healthSuccess(const []),
      consumption: consumptionSuccess(const []),
      lowStock: const LowStockEvaluationFailure(
        LowStockFailure(
          code: LowStockFailureCode.inconsistentUpstreamData,
          message: 'prediction unavailable',
        ),
      ),
    ).evaluateInventory() as ShoppingRecommendationEvaluationFailure;
    expect(result.failure.code,
        ShoppingRecommendationFailureCode.upstreamLowStockFailure);
  });

  test('duplicate Health identifiers fail the batch', () async {
    final input = recommendationInput();
    final result = await service(
      health: healthSuccess([input.healthResult, input.healthResult]),
      consumption: consumptionSuccess([input.consumptionResult]),
      lowStock: lowStockSuccess([input.lowStockResult]),
    ).evaluateInventory() as ShoppingRecommendationEvaluationFailure;
    expect(result.failure.code,
        ShoppingRecommendationFailureCode.duplicateProductId);
  });

  test('ambiguous Consumption identifiers fail the batch', () async {
    final input = recommendationInput();
    final result = await service(
      health: healthSuccess([input.healthResult]),
      consumption: consumptionSuccess(
        [input.consumptionResult],
        failures: const {
          'rice': ConsumptionFailure(
            code: ConsumptionFailureCode.invalidEvent,
            message: 'bad history',
            productId: 'rice',
          ),
        },
      ),
      lowStock: lowStockSuccess([input.lowStockResult]),
    ).evaluateInventory() as ShoppingRecommendationEvaluationFailure;
    expect(result.failure.code,
        ShoppingRecommendationFailureCode.duplicateProductId);
  });

  test('ambiguous Low Stock identifiers fail the batch', () async {
    final input = recommendationInput();
    final result = await service(
      health: healthSuccess([input.healthResult]),
      consumption: consumptionSuccess([input.consumptionResult]),
      lowStock: lowStockSuccess(
        [input.lowStockResult],
        failures: const {
          'rice': LowStockFailure(
            code: LowStockFailureCode.evaluationFailed,
            message: 'bad prediction',
            productId: 'rice',
          ),
        },
      ),
    ).evaluateInventory() as ShoppingRecommendationEvaluationFailure;
    expect(result.failure.code,
        ShoppingRecommendationFailureCode.duplicateProductId);
  });

  test('product failures and missing pairs preserve valid products', () async {
    final valid = recommendationInput();
    final brokenHealth = healthResult(id: 'broken');
    final missingHealth = healthResult(id: 'missing');
    final result = await service(
      health: healthSuccess([
        valid.healthResult,
        brokenHealth,
        missingHealth,
      ]),
      consumption: consumptionSuccess(
        [valid.consumptionResult],
        failures: const {
          'broken': ConsumptionFailure(
            code: ConsumptionFailureCode.invalidEvent,
            message: 'bad history',
            productId: 'broken',
          ),
        },
      ),
      lowStock: lowStockSuccess([valid.lowStockResult]),
    ).evaluateInventory() as ShoppingRecommendationEvaluationSuccess;
    expect(result.results.single.productId, 'rice');
    expect(result.failures['broken']?.code,
        ShoppingRecommendationFailureCode.upstreamConsumptionFailure);
    expect(result.failures['missing']?.code,
        ShoppingRecommendationFailureCode.missingPairedResult);
  });

  test('engine exceptions are isolated during a large linear batch', () async {
    final health = <InventoryHealthResult>[];
    final consumption = <ConsumptionResult>[];
    final lowStock = <LowStockResult>[];
    for (var index = 0; index < 2000; index++) {
      final input = recommendationInput(
        health: healthResult(id: 'product-$index'),
        consumption: consumptionResult(id: 'product-$index'),
      );
      health.add(input.healthResult);
      consumption.add(input.consumptionResult);
      lowStock.add(input.lowStockResult);
    }
    final engine = _SelectiveThrowingEngine('product-1000');
    final result = await service(
      health: healthSuccess(health),
      consumption: consumptionSuccess(consumption),
      lowStock: lowStockSuccess(lowStock),
      engine: engine,
    ).evaluateInventory() as ShoppingRecommendationEvaluationSuccess;
    expect(engine.calls, 2000);
    expect(result.results, hasLength(1999));
    expect(result.failures['product-1000']?.code,
        ShoppingRecommendationFailureCode.evaluationFailed);
  });

  test('LowStockService evaluateInventory remains backward compatible',
      () async {
    final input = recommendationInput();
    final health = _HealthService(healthSuccess([input.healthResult]));
    final consumption =
        _ConsumptionService(consumptionSuccess([input.consumptionResult]));
    final service = LowStockService(
      healthService: health,
      consumptionService: consumption,
    );
    final original =
        await service.evaluateInventory() as LowStockEvaluationSuccess;
    final additive = service.evaluateFromResults(
      healthEvaluation: healthSuccess([input.healthResult]),
      consumptionEvaluation: consumptionSuccess([input.consumptionResult]),
    ) as LowStockEvaluationSuccess;
    expect((health.calls, consumption.calls), (1, 1));
    expect(original.results.single.prediction.state,
        additive.results.single.prediction.state);
    expect(original.failures, isEmpty);
  });
}

class _HealthService extends InventoryHealthService {
  _HealthService(this.evaluation)
      : super(inputReader: _UnusedHealthInputReader());

  final InventoryHealthEvaluation evaluation;
  int calls = 0;

  @override
  Future<InventoryHealthEvaluation> evaluateInventory() async {
    calls++;
    return evaluation;
  }
}

class _ThrowingHealthService extends InventoryHealthService {
  _ThrowingHealthService() : super(inputReader: _UnusedHealthInputReader());

  @override
  Future<InventoryHealthEvaluation> evaluateInventory() =>
      throw StateError('unavailable');
}

class _ConsumptionService extends ConsumptionService {
  _ConsumptionService(this.evaluation)
      : super(inputReader: _UnusedConsumptionInputReader());

  final ConsumptionEvaluation evaluation;
  int calls = 0;

  @override
  Future<ConsumptionEvaluation> evaluateInventory() async {
    calls++;
    return evaluation;
  }
}

class _LowStockService extends LowStockService {
  _LowStockService(this.evaluation)
      : super(
          healthService: _HealthService(
            const InventoryHealthEvaluationSuccess([]),
          ),
          consumptionService: _ConsumptionService(
            ConsumptionEvaluationSuccess(results: const [], failures: const {}),
          ),
        );

  final LowStockEvaluation evaluation;
  int calls = 0;
  InventoryHealthEvaluation? receivedHealth;
  ConsumptionEvaluation? receivedConsumption;

  @override
  LowStockEvaluation evaluateFromResults({
    required InventoryHealthEvaluation healthEvaluation,
    required ConsumptionEvaluation consumptionEvaluation,
  }) {
    calls++;
    receivedHealth = healthEvaluation;
    receivedConsumption = consumptionEvaluation;
    return evaluation;
  }
}

class _UnusedHealthInputReader implements InventoryHealthInputReader {
  @override
  Future<InventoryHealthInputBatch> read() => throw UnimplementedError();
}

class _UnusedConsumptionInputReader implements ConsumptionInputReader {
  @override
  Future<ConsumptionInputBatch> read() => throw UnimplementedError();
}

class _CountingEngine extends ShoppingRecommendationEngine {
  int calls = 0;

  @override
  ShoppingRecommendationItemEvaluation evaluate(
    ShoppingRecommendationInput input,
  ) {
    calls++;
    return super.evaluate(input);
  }
}

class _SelectiveThrowingEngine extends ShoppingRecommendationEngine {
  _SelectiveThrowingEngine(this.throwingProductId);

  final String throwingProductId;
  int calls = 0;

  @override
  ShoppingRecommendationItemEvaluation evaluate(
    ShoppingRecommendationInput input,
  ) {
    calls++;
    if (input.healthResult.productId == throwingProductId) {
      throw StateError('engine failure');
    }
    return super.evaluate(input);
  }
}
