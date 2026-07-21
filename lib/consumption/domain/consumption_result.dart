import 'consumption_failure.dart';
import 'consumption_profile.dart';
import 'consumption_snapshot.dart';

enum ConsumptionReasonCode {
  emptyHistory,
  onlyReplenishmentObserved,
  onlyAdjustmentsObserved,
  consumptionEventsObserved,
  consumptionWithInventoryChanges,
}

class ConsumptionObservationPeriod {
  const ConsumptionObservationPeriod({required this.start, required this.end});

  final DateTime? start;
  final DateTime? end;

  Duration? get duration =>
      start == null || end == null ? null : end!.difference(start!);
}

class ConsumptionExplanation {
  const ConsumptionExplanation({
    required this.pattern,
    required this.reasonCode,
    required this.eventCount,
    required this.consumptionEventCount,
    required this.observationPeriod,
    this.summary,
  });

  final ConsumptionPattern pattern;
  final ConsumptionReasonCode reasonCode;
  final int eventCount;
  final int consumptionEventCount;
  final ConsumptionObservationPeriod observationPeriod;
  final String? summary;
}

class ConsumptionResult {
  const ConsumptionResult({
    required this.snapshot,
    required this.profile,
    required this.explanation,
  });

  final ConsumptionSnapshot snapshot;
  final ConsumptionProfile profile;
  final ConsumptionExplanation explanation;
}

sealed class ConsumptionItemEvaluation {
  const ConsumptionItemEvaluation();
}

class ConsumptionItemSuccess extends ConsumptionItemEvaluation {
  const ConsumptionItemSuccess(this.result);

  final ConsumptionResult result;
}

class ConsumptionItemFailure extends ConsumptionItemEvaluation {
  const ConsumptionItemFailure(this.failure);

  final ConsumptionFailure failure;
}

sealed class ConsumptionEvaluation {
  const ConsumptionEvaluation();
}

class ConsumptionEvaluationSuccess extends ConsumptionEvaluation {
  ConsumptionEvaluationSuccess({
    required Iterable<ConsumptionResult> results,
    required Map<String, ConsumptionFailure> failures,
  })  : results = List.unmodifiable(results),
        failures = Map.unmodifiable(failures);

  final List<ConsumptionResult> results;
  final Map<String, ConsumptionFailure> failures;
}

class ConsumptionEvaluationFailure extends ConsumptionEvaluation {
  const ConsumptionEvaluationFailure(this.failure);

  final ConsumptionFailure failure;
}
