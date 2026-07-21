import 'consumption_event.dart';

enum ConsumptionPattern {
  noHistory,
  noObservedConsumption,
  adjustmentOnly,
  consumptionObserved,
  consumptionWithOtherChanges,
}

class ConsumptionProfile {
  ConsumptionProfile({
    required this.productId,
    required this.startingQuantity,
    required this.currentQuantity,
    required this.unit,
    required Iterable<ConsumptionEvent> events,
    required this.totalConsumed,
    required this.consumptionEventCount,
    required this.totalReplenished,
    required this.totalNonConsumptionReduction,
    required this.hasInferredStartingBalance,
  }) : events = List.unmodifiable(events);

  final String productId;
  final double startingQuantity;
  final double currentQuantity;
  final String unit;
  final List<ConsumptionEvent> events;
  final double totalConsumed;
  final int consumptionEventCount;
  final double totalReplenished;
  final double totalNonConsumptionReduction;
  final bool hasInferredStartingBalance;

  DateTime? get observationStartedAt =>
      events.isEmpty ? null : events.first.timestamp;

  DateTime? get observationEndedAt =>
      events.isEmpty ? null : events.last.timestamp;
}
