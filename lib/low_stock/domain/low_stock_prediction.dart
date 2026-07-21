const int predictionHorizonDays = 14;
const int minimumObservationDays = 7;
const int minimumConsumptionEvents = 2;
const double lowStockComparisonEpsilon = 1e-9;

enum LowStockPredictionState { normal, monitor, lowSoon }

class LowStockPrediction {
  const LowStockPrediction({
    required this.state,
    required this.currentQuantity,
    required this.lowStockThreshold,
    required this.totalObservedConsumption,
    required this.consumptionEventCount,
    required this.observationDurationDays,
    required this.dailyConsumption,
    required this.projectedQuantity,
    this.predictionHorizonDays = 14,
  });

  final LowStockPredictionState state;
  final double currentQuantity;
  final double? lowStockThreshold;
  final double totalObservedConsumption;
  final int consumptionEventCount;
  final double? observationDurationDays;
  final double? dailyConsumption;
  final int predictionHorizonDays;
  final double? projectedQuantity;
}
