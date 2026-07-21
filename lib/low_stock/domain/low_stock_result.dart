import '../../consumption/domain/consumption_profile.dart';
import '../../inventory_health/domain/inventory_health_result.dart';
import 'low_stock_failure.dart';
import 'low_stock_prediction.dart';

enum LowStockReasonCode {
  insufficientHealthEvidence,
  alreadyOutOfStock,
  alreadyLowStock,
  noConsumptionEvidence,
  invalidObservationWindow,
  observationPeriodTooShort,
  insufficientConsumptionEvents,
  noPositiveConsumptionRate,
  projectedBelowThreshold,
  projectedAtThreshold,
  projectedAboveThreshold,
}

class LowStockExplanation {
  const LowStockExplanation({
    required this.prediction,
    required this.reasonCode,
    required this.healthState,
    required this.consumptionPattern,
    required this.evidence,
    this.summary,
  });

  final LowStockPredictionState prediction;
  final LowStockReasonCode reasonCode;
  final InventoryHealthStatus healthState;
  final ConsumptionPattern consumptionPattern;
  final LowStockPrediction evidence;
  final String? summary;
}

class LowStockResult {
  const LowStockResult({
    required this.productId,
    required this.productName,
    required this.category,
    required this.prediction,
    required this.explanation,
  });

  final String productId;
  final String productName;
  final String category;
  final LowStockPrediction prediction;
  final LowStockExplanation explanation;
}

sealed class LowStockItemEvaluation {
  const LowStockItemEvaluation();
}

class LowStockItemSuccess extends LowStockItemEvaluation {
  const LowStockItemSuccess(this.result);

  final LowStockResult result;
}

class LowStockItemFailure extends LowStockItemEvaluation {
  const LowStockItemFailure(this.failure);

  final LowStockFailure failure;
}

sealed class LowStockEvaluation {
  const LowStockEvaluation();
}

class LowStockEvaluationSuccess extends LowStockEvaluation {
  LowStockEvaluationSuccess({
    required Iterable<LowStockResult> results,
    required Map<String, LowStockFailure> failures,
  })  : results = List.unmodifiable(results),
        failures = Map.unmodifiable(failures);

  final List<LowStockResult> results;
  final Map<String, LowStockFailure> failures;
}

class LowStockEvaluationFailure extends LowStockEvaluation {
  const LowStockEvaluationFailure(this.failure);

  final LowStockFailure failure;
}
