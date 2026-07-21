import 'dart:math' as math;

import '../../inventory_health/domain/inventory_health_result.dart';
import '../../low_stock/domain/low_stock_prediction.dart';
import '../../low_stock/domain/low_stock_result.dart';
import '../domain/shopping_recommendation.dart';
import '../domain/shopping_recommendation_explanation.dart';
import '../domain/shopping_recommendation_failure.dart';
import '../domain/shopping_recommendation_input.dart';
import '../domain/shopping_recommendation_result.dart';

const double shoppingRecommendationComparisonEpsilon = 1e-9;

class ShoppingRecommendationEngine {
  const ShoppingRecommendationEngine();

  ShoppingRecommendationItemEvaluation evaluate(
    ShoppingRecommendationInput input,
  ) {
    final health = input.healthResult;
    final consumption = input.consumptionResult;
    final lowStock = input.lowStockResult;
    final snapshot = consumption.snapshot;
    final profile = consumption.profile;

    if (health.productId.trim().isEmpty ||
        health.productId != snapshot.productId ||
        health.productId != profile.productId ||
        health.productId != lowStock.productId) {
      return _failure(
        health.productId,
        ShoppingRecommendationFailureCode.productIdMismatch,
        'Upstream results do not identify the same product.',
      );
    }
    final unit = health.explanation.unit;
    if (!_sameUnit(unit, snapshot.unit) || !_sameUnit(unit, profile.unit)) {
      return _failure(
        health.productId,
        ShoppingRecommendationFailureCode.unitMismatch,
        'Upstream results use incompatible quantity units.',
      );
    }
    final quantities = [
      health.explanation.quantity,
      snapshot.currentQuantity,
      profile.currentQuantity,
      lowStock.prediction.currentQuantity,
    ];
    if (quantities.any((value) => !value.isFinite || value < 0)) {
      return _failure(
        health.productId,
        ShoppingRecommendationFailureCode.invalidNumericInput,
        'Upstream results contain an invalid quantity.',
      );
    }
    if (quantities.skip(1).any(
          (value) => !_nearlyEqual(value, quantities.first),
        )) {
      return _failure(
        health.productId,
        ShoppingRecommendationFailureCode.quantityMismatch,
        'Upstream results contain inconsistent current quantities.',
      );
    }
    if (!_validConsumption(input)) {
      return _failure(
        health.productId,
        ShoppingRecommendationFailureCode.invalidConsumptionEvidence,
        'The Consumption result is internally inconsistent.',
      );
    }
    if (!_validHealth(health)) {
      return _failure(
        health.productId,
        ShoppingRecommendationFailureCode.inconsistentHealthEvidence,
        'The Health result is internally inconsistent.',
      );
    }
    if (!_validLowStock(input)) {
      return _failure(
        health.productId,
        ShoppingRecommendationFailureCode.inconsistentLowStockEvidence,
        'The Low Stock result is internally inconsistent.',
      );
    }

    final decision = _decision(lowStock.prediction.state, health.status);
    if (decision == null) {
      return _failure(
        health.productId,
        ShoppingRecommendationFailureCode.unsupportedCombination,
        'The Health state and Low Stock prediction are not an approved pair.',
      );
    }
    final evidence = ShoppingRecommendation(
      state: decision.state,
      currentQuantity: health.explanation.quantity,
      unit: unit,
      totalObservedConsumption: profile.totalConsumed,
      consumptionEventCount: profile.consumptionEventCount,
    );
    return ShoppingRecommendationItemSuccess(
      ShoppingRecommendationResult(
        productId: health.productId,
        productName: health.productName,
        category: health.category,
        recommendation: evidence,
        explanation: ShoppingRecommendationExplanation(
          recommendation: decision.state,
          reasonCode: decision.reason,
          healthState: health.status,
          consumptionPattern: consumption.explanation.pattern,
          consumptionSummary: consumption.explanation.summary,
          lowStockPrediction: lowStock.prediction.state,
          evidence: evidence,
          summary: _summary(decision.reason),
        ),
      ),
    );
  }

  bool _validConsumption(ShoppingRecommendationInput input) {
    final result = input.consumptionResult;
    final profile = result.profile;
    final explanation = result.explanation;
    return profile.startingQuantity.isFinite &&
        profile.startingQuantity >= 0 &&
        profile.totalConsumed.isFinite &&
        profile.totalConsumed >= 0 &&
        profile.totalReplenished.isFinite &&
        profile.totalReplenished >= 0 &&
        profile.totalNonConsumptionReduction.isFinite &&
        profile.totalNonConsumptionReduction >= 0 &&
        profile.consumptionEventCount >= 0 &&
        explanation.eventCount >= profile.consumptionEventCount &&
        explanation.consumptionEventCount == profile.consumptionEventCount;
  }

  bool _validHealth(InventoryHealthResult health) {
    final evidence = health.explanation;
    if (evidence.status != health.status || evidence.unit.trim().isEmpty) {
      return false;
    }
    return switch (health.status) {
      InventoryHealthStatus.unknown =>
        evidence.reasonCode == InventoryHealthReasonCode.missingPolicy,
      InventoryHealthStatus.outOfStock =>
        evidence.reasonCode == InventoryHealthReasonCode.quantityIsZero &&
            _nearlyEqual(evidence.quantity, 0),
      InventoryHealthStatus.lowStock => evidence.reasonCode ==
              InventoryHealthReasonCode.quantityAtOrBelowThreshold &&
          _validThreshold(evidence.threshold) &&
          _compare(evidence.quantity, evidence.threshold!) <= 0,
      InventoryHealthStatus.healthy => evidence.reasonCode ==
              InventoryHealthReasonCode.quantityAboveThreshold &&
          _validThreshold(evidence.threshold) &&
          _compare(evidence.quantity, evidence.threshold!) > 0,
    };
  }

  bool _validLowStock(ShoppingRecommendationInput input) {
    final result = input.lowStockResult;
    final health = input.healthResult;
    final consumption = input.consumptionResult;
    final prediction = result.prediction;
    final explanation = result.explanation;
    final evidence = explanation.evidence;
    if (prediction.state != explanation.prediction ||
        explanation.healthState != health.status ||
        evidence.state != prediction.state ||
        !_nearlyEqual(
          evidence.currentQuantity,
          prediction.currentQuantity,
        ) ||
        !_sameOptional(
            evidence.lowStockThreshold, prediction.lowStockThreshold) ||
        !_nearlyEqual(evidence.totalObservedConsumption,
            prediction.totalObservedConsumption) ||
        evidence.consumptionEventCount != prediction.consumptionEventCount ||
        !_sameOptional(evidence.observationDurationDays,
            prediction.observationDurationDays) ||
        !_sameOptional(
            evidence.dailyConsumption, prediction.dailyConsumption) ||
        evidence.predictionHorizonDays != prediction.predictionHorizonDays ||
        !_sameOptional(
            evidence.projectedQuantity, prediction.projectedQuantity) ||
        !_nearlyEqual(prediction.totalObservedConsumption,
            consumption.profile.totalConsumed) ||
        prediction.consumptionEventCount !=
            consumption.profile.consumptionEventCount ||
        explanation.consumptionPattern != consumption.explanation.pattern) {
      return false;
    }
    return switch ((prediction.state, health.status)) {
      (LowStockPredictionState.lowSoon, InventoryHealthStatus.outOfStock) =>
        explanation.reasonCode == LowStockReasonCode.alreadyOutOfStock,
      (LowStockPredictionState.lowSoon, InventoryHealthStatus.lowStock) =>
        explanation.reasonCode == LowStockReasonCode.alreadyLowStock,
      (LowStockPredictionState.lowSoon, InventoryHealthStatus.healthy) =>
        explanation.reasonCode == LowStockReasonCode.projectedBelowThreshold ||
            explanation.reasonCode == LowStockReasonCode.projectedAtThreshold,
      (LowStockPredictionState.monitor, InventoryHealthStatus.healthy) =>
        explanation.reasonCode == LowStockReasonCode.noConsumptionEvidence ||
            explanation.reasonCode ==
                LowStockReasonCode.invalidObservationWindow ||
            explanation.reasonCode ==
                LowStockReasonCode.observationPeriodTooShort ||
            explanation.reasonCode ==
                LowStockReasonCode.insufficientConsumptionEvents,
      (LowStockPredictionState.monitor, InventoryHealthStatus.unknown) =>
        explanation.reasonCode == LowStockReasonCode.insufficientHealthEvidence,
      (LowStockPredictionState.normal, InventoryHealthStatus.healthy) =>
        explanation.reasonCode ==
                LowStockReasonCode.noPositiveConsumptionRate ||
            explanation.reasonCode ==
                LowStockReasonCode.projectedAboveThreshold,
      _ => true,
    };
  }

  _RecommendationDecision? _decision(
    LowStockPredictionState prediction,
    InventoryHealthStatus health,
  ) =>
      switch ((prediction, health)) {
        (LowStockPredictionState.lowSoon, InventoryHealthStatus.outOfStock) =>
          const _RecommendationDecision(
            ShoppingRecommendationState.buyNow,
            ShoppingRecommendationReasonCode.alreadyOutOfStock,
          ),
        (LowStockPredictionState.lowSoon, InventoryHealthStatus.lowStock) =>
          const _RecommendationDecision(
            ShoppingRecommendationState.buySoon,
            ShoppingRecommendationReasonCode.alreadyLowStock,
          ),
        (LowStockPredictionState.lowSoon, InventoryHealthStatus.healthy) =>
          const _RecommendationDecision(
            ShoppingRecommendationState.buySoon,
            ShoppingRecommendationReasonCode.projectedLowSoon,
          ),
        (LowStockPredictionState.monitor, InventoryHealthStatus.healthy) =>
          const _RecommendationDecision(
            ShoppingRecommendationState.watch,
            ShoppingRecommendationReasonCode.monitoringRecommended,
          ),
        (LowStockPredictionState.monitor, InventoryHealthStatus.unknown) =>
          const _RecommendationDecision(
            ShoppingRecommendationState.watch,
            ShoppingRecommendationReasonCode.insufficientHealthEvidence,
          ),
        (LowStockPredictionState.normal, InventoryHealthStatus.healthy) =>
          const _RecommendationDecision(
            ShoppingRecommendationState.ignore,
            ShoppingRecommendationReasonCode.healthyNoAction,
          ),
        _ => null,
      };

  bool _sameUnit(String left, String right) =>
      left.trim().isNotEmpty &&
      left.trim().toLowerCase() == right.trim().toLowerCase();

  bool _validThreshold(double? value) =>
      value != null && value.isFinite && value >= 0;

  bool _sameOptional(double? left, double? right) =>
      left == null && right == null ||
      left != null && right != null && _nearlyEqual(left, right);

  bool _nearlyEqual(double left, double right) =>
      left.isFinite && right.isFinite && _compare(left, right) == 0;

  int _compare(double left, double right) {
    final scale = math.max(1, math.max(left.abs(), right.abs()));
    if ((left - right).abs() <=
        shoppingRecommendationComparisonEpsilon * scale) {
      return 0;
    }
    return left < right ? -1 : 1;
  }

  String _summary(ShoppingRecommendationReasonCode reason) => switch (reason) {
        ShoppingRecommendationReasonCode.alreadyOutOfStock =>
          'Buy now because this product is already out of stock.',
        ShoppingRecommendationReasonCode.alreadyLowStock =>
          'Buy soon because this product is already low in stock.',
        ShoppingRecommendationReasonCode.projectedLowSoon =>
          'Buy soon because the authoritative prediction is Low soon.',
        ShoppingRecommendationReasonCode.monitoringRecommended =>
          'Watch this product while more evidence is collected.',
        ShoppingRecommendationReasonCode.healthyNoAction =>
          'Current evidence does not recommend a purchase.',
        ShoppingRecommendationReasonCode.insufficientHealthEvidence =>
          'Watch this product because Health evidence is insufficient.',
      };

  ShoppingRecommendationItemFailure _failure(
    String productId,
    ShoppingRecommendationFailureCode code,
    String message,
  ) =>
      ShoppingRecommendationItemFailure(
        ShoppingRecommendationFailure(
          code: code,
          message: message,
          productId: productId.trim().isEmpty ? null : productId,
        ),
      );
}

class _RecommendationDecision {
  const _RecommendationDecision(this.state, this.reason);

  final ShoppingRecommendationState state;
  final ShoppingRecommendationReasonCode reason;
}
