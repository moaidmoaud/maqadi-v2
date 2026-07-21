import 'inventory_health_result.dart';

enum InventoryHealthFailureCode {
  inputUnavailable,
  duplicateProductId,
  duplicatePolicy,
  invalidInputBatch,
  evaluationFailed,
}

class InventoryHealthFailure {
  const InventoryHealthFailure({required this.code, required this.message});

  final InventoryHealthFailureCode code;
  final String message;
}

sealed class InventoryHealthEvaluation {
  const InventoryHealthEvaluation();
}

class InventoryHealthEvaluationSuccess extends InventoryHealthEvaluation {
  const InventoryHealthEvaluationSuccess(this.results);

  final List<InventoryHealthResult> results;
}

class InventoryHealthEvaluationFailure extends InventoryHealthEvaluation {
  const InventoryHealthEvaluationFailure(this.failure);

  final InventoryHealthFailure failure;
}
