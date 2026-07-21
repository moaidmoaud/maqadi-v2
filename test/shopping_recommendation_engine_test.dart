import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/consumption/domain/consumption_profile.dart';
import 'package:maqadi_v2/consumption/domain/consumption_result.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_result.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_prediction.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_result.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_explanation.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_failure.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_input.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_result.dart';
import 'package:maqadi_v2/shopping_recommendation/engine/shopping_recommendation_engine.dart';

import 'shopping_recommendation_test_support.dart';

void main() {
  const engine = ShoppingRecommendationEngine();

  ShoppingRecommendationResult success(ShoppingRecommendationInput input) =>
      (engine.evaluate(input) as ShoppingRecommendationItemSuccess).result;

  ShoppingRecommendationFailure failure(ShoppingRecommendationInput input) =>
      (engine.evaluate(input) as ShoppingRecommendationItemFailure).failure;

  test('OutOfStock and LowSoon recommends BuyNow', () {
    final result = success(inputForStatus(InventoryHealthStatus.outOfStock));
    expect(result.recommendation.state, ShoppingRecommendationState.buyNow);
    expect(result.explanation.reasonCode,
        ShoppingRecommendationReasonCode.alreadyOutOfStock);
  });

  test('LowStock and LowSoon recommends BuySoon', () {
    final result = success(inputForStatus(InventoryHealthStatus.lowStock));
    expect(result.recommendation.state, ShoppingRecommendationState.buySoon);
    expect(result.explanation.reasonCode,
        ShoppingRecommendationReasonCode.alreadyLowStock);
  });

  test('Healthy and LowSoon recommends BuySoon', () {
    final result = success(recommendationInput(
      consumption: consumptionResult(totalConsumed: 9),
    ));
    expect(result.recommendation.state, ShoppingRecommendationState.buySoon);
    expect(result.explanation.reasonCode,
        ShoppingRecommendationReasonCode.projectedLowSoon);
  });

  test('Healthy and Monitor recommends Watch', () {
    final result = success(recommendationInput(
      consumption: consumptionResult(totalConsumed: 0, consumptionEvents: 0),
    ));
    expect(result.recommendation.state, ShoppingRecommendationState.watch);
    expect(result.explanation.reasonCode,
        ShoppingRecommendationReasonCode.monitoringRecommended);
  });

  test('Healthy and Normal recommends Ignore', () {
    final result = success(recommendationInput(
      consumption: consumptionResult(totalConsumed: 7),
    ));
    expect(result.recommendation.state, ShoppingRecommendationState.ignore);
    expect(result.explanation.reasonCode,
        ShoppingRecommendationReasonCode.healthyNoAction);
  });

  test('valid Unknown and Monitor recommends Watch', () {
    final result = success(inputForStatus(InventoryHealthStatus.unknown));
    expect(result.recommendation.state, ShoppingRecommendationState.watch);
    expect(result.explanation.reasonCode,
        ShoppingRecommendationReasonCode.insufficientHealthEvidence);
  });

  test('unsupported Health and prediction combinations fail explicitly', () {
    final valid = recommendationInput(
      consumption: consumptionResult(totalConsumed: 7),
    );
    for (final status in [
      InventoryHealthStatus.outOfStock,
      InventoryHealthStatus.lowStock,
      InventoryHealthStatus.unknown,
    ]) {
      final quantity = status == InventoryHealthStatus.outOfStock ? 0.0 : 2.0;
      final health = healthResult(
        status: status,
        quantity: status == InventoryHealthStatus.unknown ? 10 : quantity,
        threshold: status == InventoryHealthStatus.unknown ? null : 2,
      );
      final consumption = consumptionResult(
        quantity: status == InventoryHealthStatus.unknown ? 10 : quantity,
        totalConsumed: 7,
      );
      expect(
        failure(ShoppingRecommendationInput(
          healthResult: health,
          consumptionResult: consumption,
          lowStockResult: replaceLowStock(
            valid.lowStockResult,
            prediction: replacePrediction(
              valid.lowStockResult.prediction,
              currentQuantity:
                  status == InventoryHealthStatus.unknown ? 10 : quantity,
            ),
            explanation: LowStockExplanation(
              prediction: LowStockPredictionState.normal,
              reasonCode: LowStockReasonCode.projectedAboveThreshold,
              healthState: status,
              consumptionPattern: ConsumptionPattern.consumptionObserved,
              evidence: replacePrediction(
                valid.lowStockResult.prediction,
                currentQuantity:
                    status == InventoryHealthStatus.unknown ? 10 : quantity,
              ),
            ),
          ),
        )).code,
        ShoppingRecommendationFailureCode.unsupportedCombination,
      );
    }
  });

  test('Unknown caused by invalid underlying evidence fails', () {
    final input = inputForStatus(InventoryHealthStatus.unknown);
    expect(
      failure(ShoppingRecommendationInput(
        healthResult: healthResult(
          status: InventoryHealthStatus.unknown,
          reason: InventoryHealthReasonCode.invalidQuantity,
          threshold: null,
        ),
        consumptionResult: input.consumptionResult,
        lowStockResult: input.lowStockResult,
      )).code,
      ShoppingRecommendationFailureCode.inconsistentHealthEvidence,
    );
  });

  test('product ID mismatch fails', () {
    final input = recommendationInput();
    expect(
      failure(ShoppingRecommendationInput(
        healthResult: input.healthResult,
        consumptionResult: input.consumptionResult,
        lowStockResult:
            replaceLowStock(input.lowStockResult, productId: 'beans'),
      )).code,
      ShoppingRecommendationFailureCode.productIdMismatch,
    );
  });

  test('unit mismatch fails', () {
    final health = healthResult(unit: 'bag');
    final consumption = consumptionResult(unit: 'kg');
    expect(
      failure(recommendationInput(
        health: health,
        consumption: consumption,
        lowStock: lowStockResultFor(
          health,
          consumptionResult(unit: 'bag'),
        ),
      )).code,
      ShoppingRecommendationFailureCode.unitMismatch,
    );
  });

  test('quantity mismatch fails', () {
    final input = recommendationInput();
    expect(
      failure(ShoppingRecommendationInput(
        healthResult: input.healthResult,
        consumptionResult: consumptionResult(quantity: 9),
        lowStockResult: input.lowStockResult,
      )).code,
      ShoppingRecommendationFailureCode.quantityMismatch,
    );
  });

  test('non-finite quantity fails', () {
    final input = recommendationInput();
    expect(
      failure(ShoppingRecommendationInput(
        healthResult: healthResult(quantity: double.infinity),
        consumptionResult: input.consumptionResult,
        lowStockResult: input.lowStockResult,
      )).code,
      ShoppingRecommendationFailureCode.invalidNumericInput,
    );
  });

  test('centralized tolerance accepts tiny quantity differences', () {
    final health = healthResult();
    final consumption = consumptionResult(quantity: 10 + 5e-10);
    final result = success(recommendationInput(
      health: health,
      consumption: consumption,
      lowStock: lowStockResultFor(health, consumption),
    ));
    expect(result.recommendation.state, ShoppingRecommendationState.ignore);
  });

  test('malformed Healthy explanation fails', () {
    final input = recommendationInput();
    expect(
      failure(ShoppingRecommendationInput(
        healthResult: healthResult(
          reason: InventoryHealthReasonCode.quantityAtOrBelowThreshold,
        ),
        consumptionResult: input.consumptionResult,
        lowStockResult: input.lowStockResult,
      )).code,
      ShoppingRecommendationFailureCode.inconsistentHealthEvidence,
    );
  });

  test('malformed Low Stock explanation state fails', () {
    final input = recommendationInput();
    final source = input.lowStockResult;
    final malformed = replaceLowStock(
      source,
      explanation: LowStockExplanation(
        prediction: LowStockPredictionState.monitor,
        reasonCode: source.explanation.reasonCode,
        healthState: source.explanation.healthState,
        consumptionPattern: source.explanation.consumptionPattern,
        evidence: source.explanation.evidence,
      ),
    );
    expect(
      failure(ShoppingRecommendationInput(
        healthResult: input.healthResult,
        consumptionResult: input.consumptionResult,
        lowStockResult: malformed,
      )).code,
      ShoppingRecommendationFailureCode.inconsistentLowStockEvidence,
    );
  });

  test('malformed Low Stock reason fails', () {
    final input = recommendationInput(
      consumption: consumptionResult(totalConsumed: 9),
    );
    final source = input.lowStockResult;
    final malformed = replaceLowStock(
      source,
      explanation: LowStockExplanation(
        prediction: source.explanation.prediction,
        reasonCode: LowStockReasonCode.alreadyLowStock,
        healthState: source.explanation.healthState,
        consumptionPattern: source.explanation.consumptionPattern,
        evidence: source.explanation.evidence,
      ),
    );
    expect(
      failure(ShoppingRecommendationInput(
        healthResult: input.healthResult,
        consumptionResult: input.consumptionResult,
        lowStockResult: malformed,
      )).code,
      ShoppingRecommendationFailureCode.inconsistentLowStockEvidence,
    );
  });

  test('mismatched Low Stock evidence fails', () {
    final input = recommendationInput();
    final source = input.lowStockResult;
    final malformedEvidence = replacePrediction(
      source.explanation.evidence,
      totalObservedConsumption: 999,
    );
    expect(
      failure(ShoppingRecommendationInput(
        healthResult: input.healthResult,
        consumptionResult: input.consumptionResult,
        lowStockResult: replaceLowStock(
          source,
          explanation: LowStockExplanation(
            prediction: source.explanation.prediction,
            reasonCode: source.explanation.reasonCode,
            healthState: source.explanation.healthState,
            consumptionPattern: source.explanation.consumptionPattern,
            evidence: malformedEvidence,
          ),
        ),
      )).code,
      ShoppingRecommendationFailureCode.inconsistentLowStockEvidence,
    );
  });

  test('invalid Consumption aggregates fail', () {
    final input = recommendationInput();
    final source = input.consumptionResult;
    final malformed = ConsumptionResult(
      snapshot: source.snapshot,
      profile: ConsumptionProfile(
        productId: source.profile.productId,
        startingQuantity: source.profile.startingQuantity,
        currentQuantity: source.profile.currentQuantity,
        unit: source.profile.unit,
        events: const [],
        totalConsumed: double.nan,
        consumptionEventCount: source.profile.consumptionEventCount,
        totalReplenished: source.profile.totalReplenished,
        totalNonConsumptionReduction:
            source.profile.totalNonConsumptionReduction,
        hasInferredStartingBalance: false,
      ),
      explanation: source.explanation,
    );
    expect(
      failure(ShoppingRecommendationInput(
        healthResult: input.healthResult,
        consumptionResult: malformed,
        lowStockResult: input.lowStockResult,
      )).code,
      ShoppingRecommendationFailureCode.invalidConsumptionEvidence,
    );
  });

  test('Consumption evidence is copied into the explanation', () {
    final result = success(recommendationInput(
      consumption: consumptionResult(
        totalConsumed: 7,
        consumptionEvents: 4,
        pattern: ConsumptionPattern.consumptionWithOtherChanges,
      ),
    ));
    expect(result.explanation.consumptionPattern,
        ConsumptionPattern.consumptionWithOtherChanges);
    expect(result.explanation.consumptionSummary, 'Consumption summary');
    expect(result.explanation.evidence.totalObservedConsumption, 7);
    expect(result.explanation.evidence.consumptionEventCount, 4);
  });

  test('Consumption never upgrades or downgrades the recommendation', () {
    final input = recommendationInput(
      consumption: consumptionResult(totalConsumed: 7),
    );
    for (final pattern in ConsumptionPattern.values) {
      final consumption = consumptionResult(
        totalConsumed: 7,
        totalReplenished: pattern.index * 10,
        totalOtherReduction: pattern.index * 5,
        pattern: pattern,
      );
      final result = success(ShoppingRecommendationInput(
        healthResult: input.healthResult,
        consumptionResult: consumption,
        lowStockResult: replaceLowStock(
          input.lowStockResult,
          explanation: LowStockExplanation(
            prediction: input.lowStockResult.explanation.prediction,
            reasonCode: input.lowStockResult.explanation.reasonCode,
            healthState: input.lowStockResult.explanation.healthState,
            consumptionPattern: pattern,
            evidence: input.lowStockResult.explanation.evidence,
            summary: input.lowStockResult.explanation.summary,
          ),
        ),
      ));
      expect(result.recommendation.state, ShoppingRecommendationState.ignore);
    }
  });

  test('result explanation contains all authoritative decision fields', () {
    final result = success(inputForStatus(InventoryHealthStatus.lowStock));
    expect(result.explanation.recommendation, result.recommendation.state);
    expect(result.explanation.healthState, InventoryHealthStatus.lowStock);
    expect(
        result.explanation.lowStockPrediction, LowStockPredictionState.lowSoon);
    expect(result.explanation.evidence, same(result.recommendation));
    expect(result.explanation.summary, isNotEmpty);
  });

  test('identical Results produce deterministic recommendations', () {
    final input = recommendationInput();
    final first = success(input);
    final second = success(input);
    expect(second.recommendation.state, first.recommendation.state);
    expect(second.explanation.reasonCode, first.explanation.reasonCode);
    expect(second.explanation.summary, first.explanation.summary);
  });

  test('recommendation evidence is immutable by construction', () {
    final result = success(recommendationInput());
    expect(result.recommendation.currentQuantity, 10);
    expect(result.recommendation.unit, 'bag');
    expect(result.recommendation.consumptionEventCount, 2);
  });
}
