import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_result.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_failure.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_input.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_prediction.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_result.dart';
import 'package:maqadi_v2/low_stock/engine/low_stock_engine.dart';

import 'low_stock_test_support.dart';

void main() {
  const engine = LowStockEngine();

  LowStockResult success(LowStockInput input) =>
      (engine.evaluate(input) as LowStockItemSuccess).result;

  LowStockFailure failure(LowStockInput input) =>
      (engine.evaluate(input) as LowStockItemFailure).failure;

  test('Unknown health becomes Monitor when policy evidence is missing', () {
    final result = success(lowStockInput(
      health: healthResult(
        status: InventoryHealthStatus.unknown,
        threshold: null,
      ),
    ));
    expect(result.prediction.state, LowStockPredictionState.monitor);
    expect(result.explanation.reasonCode,
        LowStockReasonCode.insufficientHealthEvidence);
  });

  test('malformed Unknown health is a product failure', () {
    for (final reason in [
      InventoryHealthReasonCode.invalidQuantity,
      InventoryHealthReasonCode.invalidThreshold,
    ]) {
      expect(
        failure(lowStockInput(
          health: healthResult(
            status: InventoryHealthStatus.unknown,
            reason: reason,
            threshold: null,
          ),
        )).code,
        LowStockFailureCode.inconsistentUpstreamData,
      );
    }
  });

  test('OutOfStock becomes LowSoon immediately', () {
    final result = success(lowStockInput(
      health: healthResult(
        status: InventoryHealthStatus.outOfStock,
        quantity: 0,
        threshold: 2,
      ),
      consumption: consumptionResult(quantity: 0),
    ));
    expect(result.prediction.state, LowStockPredictionState.lowSoon);
    expect(result.explanation.reasonCode, LowStockReasonCode.alreadyOutOfStock);
  });

  test('LowStock becomes LowSoon immediately', () {
    final result = success(lowStockInput(
      health: healthResult(
        status: InventoryHealthStatus.lowStock,
        quantity: 2,
      ),
      consumption: consumptionResult(quantity: 2),
    ));
    expect(result.prediction.state, LowStockPredictionState.lowSoon);
    expect(result.explanation.reasonCode, LowStockReasonCode.alreadyLowStock);
  });

  test('Healthy without actual consumption becomes Monitor', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(totalConsumed: 0, consumptionEvents: 0),
    ));
    expect(result.prediction.state, LowStockPredictionState.monitor);
    expect(result.explanation.reasonCode,
        LowStockReasonCode.noConsumptionEvidence);
  });

  test('zero observation duration becomes Monitor', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(
        start: lowStockTestTime,
        end: lowStockTestTime,
      ),
    ));
    expect(result.explanation.reasonCode,
        LowStockReasonCode.invalidObservationWindow);
  });

  test('negative observation chronology is a product failure', () {
    final result = failure(lowStockInput(
      consumption: consumptionResult(
        start: lowStockTestTime,
        end: lowStockTestTime.subtract(const Duration(seconds: 1)),
      ),
    ));
    expect(result.code, LowStockFailureCode.invalidObservationPeriod);
  });

  test('an observation shorter than seven days becomes Monitor', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(
        end: lowStockTestTime.add(const Duration(days: 6, hours: 23)),
      ),
    ));
    expect(result.explanation.reasonCode,
        LowStockReasonCode.observationPeriodTooShort);
  });

  test('seven days and two events meet the minimum evidence boundaries', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(
        totalConsumed: 1,
        consumptionEvents: 2,
        end: lowStockTestTime.add(const Duration(days: 7)),
      ),
    ));
    expect(result.prediction.observationDurationDays, 7);
    expect(result.prediction.dailyConsumption, closeTo(1 / 7, 1e-12));
    expect(result.explanation.reasonCode,
        LowStockReasonCode.projectedAboveThreshold);
  });

  test('one actual consumption event becomes Monitor', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(consumptionEvents: 1),
    ));
    expect(result.explanation.reasonCode,
        LowStockReasonCode.insufficientConsumptionEvents);
  });

  test('daily consumption uses only aggregate consumption evidence', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(
        totalConsumed: 8,
        consumptionEvents: 4,
        totalReplenished: 100,
        totalOtherReduction: 50,
      ),
    ));
    expect(result.prediction.dailyConsumption, closeTo(8 / 14, 1e-12));
    expect(result.prediction.predictionHorizonDays, 14);
  });

  test('non-positive daily consumption is Normal', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(totalConsumed: 0, consumptionEvents: 2),
    ));
    expect(result.prediction.state, LowStockPredictionState.normal);
    expect(result.explanation.reasonCode,
        LowStockReasonCode.noPositiveConsumptionRate);
  });

  test('projection below threshold is LowSoon', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(totalConsumed: 9),
    ));
    expect(result.prediction.projectedQuantity, 1);
    expect(result.explanation.reasonCode,
        LowStockReasonCode.projectedBelowThreshold);
  });

  test('projection equal to threshold is LowSoon', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(totalConsumed: 8),
    ));
    expect(result.prediction.projectedQuantity, 2);
    expect(result.prediction.state, LowStockPredictionState.lowSoon);
    expect(
        result.explanation.reasonCode, LowStockReasonCode.projectedAtThreshold);
  });

  test('centralized epsilon treats a near-equal projection as equal', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(totalConsumed: 8 - 5e-10),
    ));
    expect(
        result.explanation.reasonCode, LowStockReasonCode.projectedAtThreshold);
  });

  test('projection above threshold is Normal', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(totalConsumed: 7),
    ));
    expect(result.prediction.projectedQuantity, 3);
    expect(result.explanation.reasonCode,
        LowStockReasonCode.projectedAboveThreshold);
  });

  test('fractional observation days are preserved', () {
    final result = success(lowStockInput(
      consumption: consumptionResult(
        totalConsumed: 7.5,
        end: lowStockTestTime.add(const Duration(days: 7, hours: 12)),
      ),
    ));
    expect(result.prediction.observationDurationDays, 7.5);
    expect(result.prediction.dailyConsumption, 1);
  });

  test('product identity mismatch is rejected', () {
    expect(
      failure(lowStockInput(consumption: consumptionResult(id: 'beans'))).code,
      LowStockFailureCode.productIdMismatch,
    );
  });

  test('unit mismatch is rejected', () {
    expect(
      failure(lowStockInput(consumption: consumptionResult(unit: 'kg'))).code,
      LowStockFailureCode.unitMismatch,
    );
  });

  test('quantity mismatch is rejected', () {
    expect(
      failure(lowStockInput(consumption: consumptionResult(quantity: 9))).code,
      LowStockFailureCode.quantityMismatch,
    );
  });

  test('non-finite quantities are rejected explicitly', () {
    expect(
      failure(lowStockInput(
        health: healthResult(quantity: double.infinity),
      )).code,
      LowStockFailureCode.invalidNumericInput,
    );
  });

  test('invalid threshold relationships are rejected', () {
    expect(
      failure(lowStockInput(
        health: healthResult(quantity: 2, threshold: 2),
        consumption: consumptionResult(quantity: 2),
      )).code,
      LowStockFailureCode.inconsistentUpstreamData,
    );
    expect(
      failure(lowStockInput(
        health: healthResult(
          status: InventoryHealthStatus.lowStock,
          quantity: 3,
          threshold: 2,
        ),
        consumption: consumptionResult(quantity: 3),
      )).code,
      LowStockFailureCode.inconsistentUpstreamData,
    );
  });

  test('every successful result has a structured explanation', () {
    final result = success(lowStockInput());
    expect(result.explanation.prediction, result.prediction.state);
    expect(result.explanation.healthState, InventoryHealthStatus.healthy);
    expect(result.explanation.consumptionPattern.name, 'consumptionObserved');
    expect(result.explanation.evidence, same(result.prediction));
    expect(result.explanation.summary, isNotEmpty);
  });

  test('evaluation is deterministic for identical immutable results', () {
    final input = lowStockInput();
    final first = success(input);
    final second = success(input);
    expect(second.prediction.state, first.prediction.state);
    expect(second.prediction.projectedQuantity,
        first.prediction.projectedQuantity);
    expect(second.explanation.reasonCode, first.explanation.reasonCode);
    expect(second.explanation.summary, first.explanation.summary);
  });
}
