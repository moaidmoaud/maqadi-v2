import '../domain/consumption_failure.dart';
import '../domain/consumption_result.dart';
import '../engine/consumption_engine.dart';
import 'consumption_input_reader.dart';

class ConsumptionService {
  const ConsumptionService({
    required ConsumptionInputReader inputReader,
    ConsumptionEngine engine = const ConsumptionEngine(),
  })  : _inputReader = inputReader,
        _engine = engine;

  final ConsumptionInputReader _inputReader;
  final ConsumptionEngine _engine;

  Future<ConsumptionEvaluation> evaluateInventory() async {
    final ConsumptionInputBatch input;
    try {
      input = await _inputReader.read();
    } catch (_) {
      return const ConsumptionEvaluationFailure(
        ConsumptionFailure(
          code: ConsumptionFailureCode.inputUnavailable,
          message: 'Consumption history could not be loaded.',
        ),
      );
    }

    final ids = <String>{};
    for (final snapshot in input.snapshots) {
      if (!ids.add(snapshot.productId)) {
        return const ConsumptionEvaluationFailure(
          ConsumptionFailure(
            code: ConsumptionFailureCode.duplicateProductId,
            message: 'Inventory contains duplicate product identifiers.',
          ),
        );
      }
    }

    try {
      final results = <ConsumptionResult>[];
      final failures = <String, ConsumptionFailure>{};
      for (final snapshot in input.snapshots) {
        final evaluation = _engine.evaluate(
          snapshot: snapshot,
          inputs: input.eventsByProduct[snapshot.productId] ?? const [],
        );
        switch (evaluation) {
          case ConsumptionItemSuccess(:final result):
            results.add(result);
          case ConsumptionItemFailure(:final failure):
            failures[snapshot.productId] = failure;
        }
      }
      return ConsumptionEvaluationSuccess(results: results, failures: failures);
    } catch (_) {
      return const ConsumptionEvaluationFailure(
        ConsumptionFailure(
          code: ConsumptionFailureCode.evaluationFailed,
          message: 'Consumption history could not be evaluated.',
        ),
      );
    }
  }
}
