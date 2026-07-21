import 'dart:math' as math;

import '../../inventory_health/domain/inventory_health_result.dart';
import '../domain/low_stock_failure.dart';
import '../domain/low_stock_input.dart';
import '../domain/low_stock_prediction.dart';
import '../domain/low_stock_result.dart';

class LowStockEngine {
  const LowStockEngine();

  LowStockItemEvaluation evaluate(LowStockInput input) {
    final health = input.healthResult;
    final consumption = input.consumptionResult;
    final snapshot = consumption.snapshot;
    final profile = consumption.profile;
    final healthEvidence = health.explanation;

    if (health.productId.trim().isEmpty ||
        health.productId != snapshot.productId ||
        health.productId != profile.productId) {
      return _failure(
        health.productId,
        LowStockFailureCode.productIdMismatch,
        'Upstream results do not identify the same product.',
      );
    }
    if (!_sameUnit(healthEvidence.unit, snapshot.unit) ||
        !_sameUnit(healthEvidence.unit, profile.unit)) {
      return _failure(
        health.productId,
        LowStockFailureCode.unitMismatch,
        'Upstream results use incompatible quantity units.',
      );
    }
    if (!_validQuantity(healthEvidence.quantity) ||
        !_validQuantity(snapshot.currentQuantity) ||
        !_validQuantity(profile.currentQuantity)) {
      return _failure(
        health.productId,
        LowStockFailureCode.invalidNumericInput,
        'Upstream results contain an invalid quantity.',
      );
    }
    if (!_nearlyEqual(healthEvidence.quantity, snapshot.currentQuantity) ||
        !_nearlyEqual(healthEvidence.quantity, profile.currentQuantity)) {
      return _failure(
        health.productId,
        LowStockFailureCode.quantityMismatch,
        'Upstream results contain inconsistent quantities.',
      );
    }
    if (!_validQuantity(profile.startingQuantity) ||
        !_validQuantity(profile.totalConsumed) ||
        !_validQuantity(profile.totalReplenished) ||
        !_validQuantity(profile.totalNonConsumptionReduction) ||
        profile.consumptionEventCount < 0 ||
        consumption.explanation.consumptionEventCount < 0 ||
        consumption.explanation.eventCount < 0 ||
        consumption.explanation.consumptionEventCount !=
            profile.consumptionEventCount ||
        consumption.explanation.eventCount < profile.consumptionEventCount) {
      return _failure(
        health.productId,
        LowStockFailureCode.invalidConsumptionProfile,
        'The Consumption result is internally inconsistent.',
      );
    }

    final period = consumption.explanation.observationPeriod;
    final observation = _observationDurationDays(period.start, period.end);
    if (observation case _InvalidObservation()) {
      return _failure(
        health.productId,
        LowStockFailureCode.invalidObservationPeriod,
        'The Consumption observation period is invalid.',
      );
    }
    final observationDays = (observation as _ValidObservation).days;
    final threshold = healthEvidence.threshold;
    final statusFailure = _validateHealthStatus(health);
    if (statusFailure != null) return statusFailure;
    if ((health.status == InventoryHealthStatus.healthy ||
            health.status == InventoryHealthStatus.lowStock) &&
        !_validThreshold(threshold)) {
      return _failure(
        health.productId,
        LowStockFailureCode.invalidThreshold,
        'The Health result does not contain a valid low-stock threshold.',
      );
    }

    if (health.status == InventoryHealthStatus.unknown) {
      return _result(
        input,
        LowStockPredictionState.monitor,
        LowStockReasonCode.insufficientHealthEvidence,
        observationDays,
        null,
        null,
      );
    }
    if (health.status == InventoryHealthStatus.outOfStock) {
      return _result(
        input,
        LowStockPredictionState.lowSoon,
        LowStockReasonCode.alreadyOutOfStock,
        observationDays,
        null,
        null,
      );
    }
    if (health.status == InventoryHealthStatus.lowStock) {
      return _result(
        input,
        LowStockPredictionState.lowSoon,
        LowStockReasonCode.alreadyLowStock,
        observationDays,
        null,
        null,
      );
    }
    if (profile.consumptionEventCount == 0) {
      return _result(
        input,
        LowStockPredictionState.monitor,
        LowStockReasonCode.noConsumptionEvidence,
        observationDays,
        null,
        null,
      );
    }
    if (observationDays == null || observationDays <= 0) {
      return _result(
        input,
        LowStockPredictionState.monitor,
        LowStockReasonCode.invalidObservationWindow,
        observationDays,
        null,
        null,
      );
    }
    if (observationDays < minimumObservationDays) {
      return _result(
        input,
        LowStockPredictionState.monitor,
        LowStockReasonCode.observationPeriodTooShort,
        observationDays,
        null,
        null,
      );
    }
    if (profile.consumptionEventCount < minimumConsumptionEvents) {
      return _result(
        input,
        LowStockPredictionState.monitor,
        LowStockReasonCode.insufficientConsumptionEvents,
        observationDays,
        null,
        null,
      );
    }

    final dailyConsumption = profile.totalConsumed / observationDays;
    if (!dailyConsumption.isFinite) {
      return _failure(
        health.productId,
        LowStockFailureCode.invalidNumericInput,
        'The derived daily consumption is not finite.',
      );
    }
    if (dailyConsumption <= 0) {
      return _result(
        input,
        LowStockPredictionState.normal,
        LowStockReasonCode.noPositiveConsumptionRate,
        observationDays,
        dailyConsumption,
        null,
      );
    }
    final projected =
        healthEvidence.quantity - (dailyConsumption * predictionHorizonDays);
    if (!projected.isFinite) {
      return _failure(
        health.productId,
        LowStockFailureCode.invalidNumericInput,
        'The projected quantity is not finite.',
      );
    }
    final comparison = _compare(projected, threshold!);
    if (comparison < 0) {
      return _result(
        input,
        LowStockPredictionState.lowSoon,
        LowStockReasonCode.projectedBelowThreshold,
        observationDays,
        dailyConsumption,
        projected,
      );
    }
    if (comparison == 0) {
      return _result(
        input,
        LowStockPredictionState.lowSoon,
        LowStockReasonCode.projectedAtThreshold,
        observationDays,
        dailyConsumption,
        projected,
      );
    }
    return _result(
      input,
      LowStockPredictionState.normal,
      LowStockReasonCode.projectedAboveThreshold,
      observationDays,
      dailyConsumption,
      projected,
    );
  }

  LowStockItemFailure? _validateHealthStatus(InventoryHealthResult health) {
    final evidence = health.explanation;
    return switch (health.status) {
      InventoryHealthStatus.unknown =>
        evidence.reasonCode == InventoryHealthReasonCode.missingPolicy
            ? null
            : _failure(
                health.productId,
                LowStockFailureCode.inconsistentUpstreamData,
                'Unknown Health state is caused by invalid underlying data.',
              ),
      InventoryHealthStatus.outOfStock =>
        evidence.reasonCode == InventoryHealthReasonCode.quantityIsZero &&
                _nearlyEqual(evidence.quantity, 0)
            ? null
            : _failure(
                health.productId,
                LowStockFailureCode.inconsistentUpstreamData,
                'Out-of-stock Health evidence is inconsistent.',
              ),
      InventoryHealthStatus.lowStock => evidence.reasonCode ==
                  InventoryHealthReasonCode.quantityAtOrBelowThreshold &&
              _validThreshold(evidence.threshold) &&
              _compare(evidence.quantity, evidence.threshold!) <= 0
          ? null
          : _failure(
              health.productId,
              LowStockFailureCode.inconsistentUpstreamData,
              'Low-stock Health evidence is inconsistent.',
            ),
      InventoryHealthStatus.healthy => evidence.reasonCode ==
                  InventoryHealthReasonCode.quantityAboveThreshold &&
              _validThreshold(evidence.threshold) &&
              _compare(evidence.quantity, evidence.threshold!) > 0
          ? null
          : _failure(
              health.productId,
              LowStockFailureCode.inconsistentUpstreamData,
              'Healthy Health evidence is inconsistent.',
            ),
    };
  }

  _Observation _observationDurationDays(DateTime? start, DateTime? end) {
    if (start == null && end == null) return const _ValidObservation(null);
    if (start == null || end == null || end.isBefore(start)) {
      return const _InvalidObservation();
    }
    return _ValidObservation(
      end.difference(start).inMicroseconds / Duration.microsecondsPerDay,
    );
  }

  LowStockItemSuccess _result(
    LowStockInput input,
    LowStockPredictionState state,
    LowStockReasonCode reasonCode,
    double? observationDays,
    double? dailyConsumption,
    double? projectedQuantity,
  ) {
    final health = input.healthResult;
    final profile = input.consumptionResult.profile;
    final prediction = LowStockPrediction(
      state: state,
      currentQuantity: health.explanation.quantity,
      lowStockThreshold: health.explanation.threshold,
      totalObservedConsumption: profile.totalConsumed,
      consumptionEventCount: profile.consumptionEventCount,
      observationDurationDays: observationDays,
      dailyConsumption: dailyConsumption,
      projectedQuantity: projectedQuantity,
    );
    return LowStockItemSuccess(
      LowStockResult(
        productId: health.productId,
        productName: health.productName,
        category: health.category,
        prediction: prediction,
        explanation: LowStockExplanation(
          prediction: state,
          reasonCode: reasonCode,
          healthState: health.status,
          consumptionPattern: input.consumptionResult.explanation.pattern,
          evidence: prediction,
          summary: _summary(reasonCode),
        ),
      ),
    );
  }

  LowStockItemFailure _failure(
    String productId,
    LowStockFailureCode code,
    String message,
  ) =>
      LowStockItemFailure(
        LowStockFailure(
          code: code,
          message: message,
          productId: productId.trim().isEmpty ? null : productId,
        ),
      );

  bool _sameUnit(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase() &&
      left.trim().isNotEmpty;

  bool _validQuantity(double value) => value.isFinite && value >= 0;

  bool _validThreshold(double? value) =>
      value != null && value.isFinite && value >= 0;

  bool _nearlyEqual(double left, double right) => _compare(left, right) == 0;

  int _compare(double left, double right) {
    final scale = math.max(1, math.max(left.abs(), right.abs()));
    if ((left - right).abs() <= lowStockComparisonEpsilon * scale) return 0;
    return left < right ? -1 : 1;
  }

  String _summary(LowStockReasonCode reason) => switch (reason) {
        LowStockReasonCode.insufficientHealthEvidence =>
          'Health evidence is insufficient for a low-stock projection.',
        LowStockReasonCode.alreadyOutOfStock =>
          'The product is already out of stock.',
        LowStockReasonCode.alreadyLowStock =>
          'The product is already at or below its low-stock threshold.',
        LowStockReasonCode.noConsumptionEvidence =>
          'No actual consumption events are available yet.',
        LowStockReasonCode.invalidObservationWindow =>
          'The observation window is not long enough to calculate a rate.',
        LowStockReasonCode.observationPeriodTooShort =>
          'At least seven observation days are required.',
        LowStockReasonCode.insufficientConsumptionEvents =>
          'At least two consumption events are required.',
        LowStockReasonCode.noPositiveConsumptionRate =>
          'Observed daily consumption is not positive.',
        LowStockReasonCode.projectedBelowThreshold =>
          'Projected stock is below the threshold within fourteen days.',
        LowStockReasonCode.projectedAtThreshold =>
          'Projected stock reaches the threshold within fourteen days.',
        LowStockReasonCode.projectedAboveThreshold =>
          'Projected stock remains above the threshold for fourteen days.',
      };
}

sealed class _Observation {
  const _Observation();
}

class _ValidObservation extends _Observation {
  const _ValidObservation(this.days);

  final double? days;
}

class _InvalidObservation extends _Observation {
  const _InvalidObservation();
}
