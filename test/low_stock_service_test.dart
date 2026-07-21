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
import 'package:maqadi_v2/low_stock/domain/low_stock_input.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_result.dart';
import 'package:maqadi_v2/low_stock/engine/low_stock_engine.dart';

import 'low_stock_test_support.dart';

void main() {
  LowStockService service({
    required InventoryHealthEvaluation health,
    required ConsumptionEvaluation consumption,
    LowStockEngine engine = const LowStockEngine(),
  }) =>
      LowStockService(
        healthService: _HealthService(health),
        consumptionService: _ConsumptionService(consumption),
        engine: engine,
      );

  InventoryHealthEvaluationSuccess healthSuccess(
    Iterable<InventoryHealthResult> results,
  ) =>
      InventoryHealthEvaluationSuccess(List.unmodifiable(results));

  ConsumptionEvaluationSuccess consumptionSuccess(
    Iterable<ConsumptionResult> results, {
    Map<String, ConsumptionFailure> failures = const {},
  }) =>
      ConsumptionEvaluationSuccess(results: results, failures: failures);

  test('evaluates both upstream batches once and each pair once', () async {
    final health = _HealthService(healthSuccess([
      healthResult(id: 'a'),
      healthResult(id: 'b'),
    ]));
    final consumption = _ConsumptionService(consumptionSuccess([
      consumptionResult(id: 'a'),
      consumptionResult(id: 'b'),
    ]));
    final engine = _CountingEngine();
    final result = await LowStockService(
      healthService: health,
      consumptionService: consumption,
      engine: engine,
    ).evaluateInventory() as LowStockEvaluationSuccess;
    expect((health.calls, consumption.calls, engine.calls), (1, 1, 2));
    expect(result.results, hasLength(2));
  });

  test('maps a complete Health batch failure', () async {
    final result = await service(
      health: const InventoryHealthEvaluationFailure(
        InventoryHealthFailure(
          code: InventoryHealthFailureCode.inputUnavailable,
          message: 'health unavailable',
        ),
      ),
      consumption: consumptionSuccess(const []),
    ).evaluateInventory() as LowStockEvaluationFailure;
    expect(result.failure.code, LowStockFailureCode.upstreamHealthFailure);
  });

  test('maps a complete Consumption batch failure', () async {
    final result = await service(
      health: healthSuccess(const []),
      consumption: const ConsumptionEvaluationFailure(
        ConsumptionFailure(
          code: ConsumptionFailureCode.inputUnavailable,
          message: 'consumption unavailable',
        ),
      ),
    ).evaluateInventory() as LowStockEvaluationFailure;
    expect(result.failure.code, LowStockFailureCode.upstreamConsumptionFailure);
  });

  test('maps unexpected upstream exceptions to a batch failure', () async {
    final result = await LowStockService(
      healthService: _ThrowingHealthService(),
      consumptionService: _ConsumptionService(consumptionSuccess(const [])),
    ).evaluateInventory() as LowStockEvaluationFailure;
    expect(result.failure.code, LowStockFailureCode.inconsistentUpstreamData);
  });

  test('unsafe duplicate Health identifiers fail the batch', () async {
    final repeated = healthResult();
    final result = await service(
      health: healthSuccess([repeated, repeated]),
      consumption: consumptionSuccess([consumptionResult()]),
    ).evaluateInventory() as LowStockEvaluationFailure;
    expect(result.failure.code, LowStockFailureCode.duplicateProductId);
  });

  test('unsafe duplicate Consumption identifiers fail the batch', () async {
    final repeated = consumptionResult();
    final result = await service(
      health: healthSuccess([healthResult()]),
      consumption: consumptionSuccess([repeated, repeated]),
    ).evaluateInventory() as LowStockEvaluationFailure;
    expect(result.failure.code, LowStockFailureCode.duplicateProductId);
  });

  test('a Consumption result and failure for one ID fail as ambiguous',
      () async {
    final result = await service(
      health: healthSuccess([healthResult()]),
      consumption: consumptionSuccess(
        [consumptionResult()],
        failures: const {
          'rice': ConsumptionFailure(
            code: ConsumptionFailureCode.invalidEvent,
            message: 'bad event',
            productId: 'rice',
          ),
        },
      ),
    ).evaluateInventory() as LowStockEvaluationFailure;
    expect(result.failure.code, LowStockFailureCode.duplicateProductId);
  });

  test('product-specific upstream failures preserve valid products', () async {
    final result = await service(
      health: healthSuccess([
        healthResult(id: 'valid'),
        healthResult(id: 'broken'),
      ]),
      consumption: consumptionSuccess(
        [consumptionResult(id: 'valid')],
        failures: const {
          'broken': ConsumptionFailure(
            code: ConsumptionFailureCode.invalidEvent,
            message: 'broken history',
            productId: 'broken',
          ),
        },
      ),
    ).evaluateInventory() as LowStockEvaluationSuccess;
    expect(result.results.single.productId, 'valid');
    expect(result.failures['broken']?.code,
        LowStockFailureCode.upstreamConsumptionFailure);
  });

  test('missing pairs become product-specific failures in both directions',
      () async {
    final result = await service(
      health: healthSuccess([healthResult(id: 'health-only')]),
      consumption: consumptionSuccess([
        consumptionResult(id: 'consumption-only'),
      ]),
    ).evaluateInventory() as LowStockEvaluationSuccess;
    expect(result.results, isEmpty);
    expect(result.failures.keys,
        containsAll(<String>['health-only', 'consumption-only']));
    expect(
        result.failures.values.every((failure) =>
            failure.code == LowStockFailureCode.missingPairedResult),
        isTrue);
  });

  test('engine failures are isolated during a large linear batch', () async {
    final health = <InventoryHealthResult>[];
    final consumption = <ConsumptionResult>[];
    for (var index = 0; index < 2000; index++) {
      final id = 'product-$index';
      health.add(healthResult(id: id));
      consumption.add(consumptionResult(id: id));
    }
    final engine = _SelectiveThrowingEngine('product-1000');
    final result = await service(
      health: healthSuccess(health),
      consumption: consumptionSuccess(consumption),
      engine: engine,
    ).evaluateInventory() as LowStockEvaluationSuccess;
    expect(engine.calls, 2000);
    expect(result.results, hasLength(1999));
    expect(result.failures['product-1000']?.code,
        LowStockFailureCode.evaluationFailed);
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

class _UnusedHealthInputReader implements InventoryHealthInputReader {
  @override
  Future<InventoryHealthInputBatch> read() => throw UnimplementedError();
}

class _UnusedConsumptionInputReader implements ConsumptionInputReader {
  @override
  Future<ConsumptionInputBatch> read() => throw UnimplementedError();
}

class _CountingEngine extends LowStockEngine {
  int calls = 0;

  @override
  LowStockItemEvaluation evaluate(LowStockInput input) {
    calls++;
    return super.evaluate(input);
  }
}

class _SelectiveThrowingEngine extends LowStockEngine {
  _SelectiveThrowingEngine(this.throwingProductId);

  final String throwingProductId;
  int calls = 0;

  @override
  LowStockItemEvaluation evaluate(LowStockInput input) {
    calls++;
    if (input.healthResult.productId == throwingProductId) {
      throw StateError('engine failure');
    }
    return super.evaluate(input);
  }
}
