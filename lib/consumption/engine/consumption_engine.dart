import '../domain/consumption_event.dart';
import '../domain/consumption_profile.dart';
import '../domain/consumption_result.dart';
import '../domain/consumption_snapshot.dart';
import 'consumption_event_builder.dart';

class ConsumptionEngine {
  const ConsumptionEngine({
    ConsumptionEventBuilder eventBuilder = const ConsumptionEventBuilder(),
  }) : _eventBuilder = eventBuilder;

  final ConsumptionEventBuilder _eventBuilder;

  ConsumptionItemEvaluation evaluate({
    required ConsumptionSnapshot snapshot,
    required List<ConsumptionEventInput> inputs,
  }) {
    final build = _eventBuilder.build(snapshot: snapshot, inputs: inputs);
    if (build case ConsumptionEventBuildFailure(:final failure)) {
      return ConsumptionItemFailure(failure);
    }
    final success = build as ConsumptionEventBuildSuccess;
    var totalConsumed = 0.0;
    var consumptionCount = 0;
    var totalReplenished = 0.0;
    var totalOtherReduction = 0.0;
    for (final event in success.events) {
      if (event.reason == ConsumptionReason.consumption && event.delta < 0) {
        totalConsumed += event.delta.abs();
        consumptionCount++;
      } else if (event.delta > 0) {
        totalReplenished += event.delta;
      } else if (event.delta < 0) {
        totalOtherReduction += event.delta.abs();
      }
    }

    final pattern = _pattern(
      events: success.events,
      consumptionCount: consumptionCount,
      totalOtherReduction: totalOtherReduction,
    );
    final profile = ConsumptionProfile(
      productId: snapshot.productId,
      startingQuantity: success.startingQuantity,
      currentQuantity: snapshot.currentQuantity,
      unit: snapshot.unit,
      events: success.events,
      totalConsumed: totalConsumed,
      consumptionEventCount: consumptionCount,
      totalReplenished: totalReplenished,
      totalNonConsumptionReduction: totalOtherReduction,
      hasInferredStartingBalance: success.startingQuantity > 0,
    );
    return ConsumptionItemSuccess(
      ConsumptionResult(
        snapshot: snapshot,
        profile: profile,
        explanation: _explanation(profile, pattern),
      ),
    );
  }

  ConsumptionPattern _pattern({
    required List<ConsumptionEvent> events,
    required int consumptionCount,
    required double totalOtherReduction,
  }) {
    if (events.isEmpty) return ConsumptionPattern.noHistory;
    if (consumptionCount == 0 && totalOtherReduction > 0) {
      return ConsumptionPattern.adjustmentOnly;
    }
    if (consumptionCount == 0) {
      return ConsumptionPattern.noObservedConsumption;
    }
    if (events.length == consumptionCount) {
      return ConsumptionPattern.consumptionObserved;
    }
    return ConsumptionPattern.consumptionWithOtherChanges;
  }

  ConsumptionExplanation _explanation(
    ConsumptionProfile profile,
    ConsumptionPattern pattern,
  ) {
    final reason = switch (pattern) {
      ConsumptionPattern.noHistory => ConsumptionReasonCode.emptyHistory,
      ConsumptionPattern.noObservedConsumption =>
        ConsumptionReasonCode.onlyReplenishmentObserved,
      ConsumptionPattern.adjustmentOnly =>
        ConsumptionReasonCode.onlyAdjustmentsObserved,
      ConsumptionPattern.consumptionObserved =>
        ConsumptionReasonCode.consumptionEventsObserved,
      ConsumptionPattern.consumptionWithOtherChanges =>
        ConsumptionReasonCode.consumptionWithInventoryChanges,
    };
    final summary = switch (pattern) {
      ConsumptionPattern.noHistory =>
        'No quantity-change history is available.',
      ConsumptionPattern.noObservedConsumption =>
        'Stock changes were observed, but none were recorded as consumption.',
      ConsumptionPattern.adjustmentOnly =>
        'Only non-consumption inventory reductions were observed.',
      ConsumptionPattern.consumptionObserved =>
        'The history contains recorded consumption events.',
      ConsumptionPattern.consumptionWithOtherChanges =>
        'Consumption was observed alongside other inventory changes.',
    };
    return ConsumptionExplanation(
      pattern: pattern,
      reasonCode: reason,
      eventCount: profile.events.length,
      consumptionEventCount: profile.consumptionEventCount,
      observationPeriod: ConsumptionObservationPeriod(
        start: profile.observationStartedAt,
        end: profile.observationEndedAt,
      ),
      summary: summary,
    );
  }
}
