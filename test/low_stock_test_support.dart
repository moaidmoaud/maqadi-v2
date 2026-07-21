import 'package:maqadi_v2/consumption/domain/consumption_profile.dart';
import 'package:maqadi_v2/consumption/domain/consumption_result.dart';
import 'package:maqadi_v2/consumption/domain/consumption_snapshot.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_result.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_input.dart';

final lowStockTestTime = DateTime.utc(2026, 7, 21, 12);

InventoryHealthResult healthResult({
  String id = 'rice',
  String name = 'Rice',
  String category = 'Grains',
  InventoryHealthStatus status = InventoryHealthStatus.healthy,
  InventoryHealthReasonCode? reason,
  double quantity = 10,
  double? threshold = 2,
  String unit = 'bag',
}) {
  final resolvedReason = reason ??
      switch (status) {
        InventoryHealthStatus.unknown =>
          InventoryHealthReasonCode.missingPolicy,
        InventoryHealthStatus.healthy =>
          InventoryHealthReasonCode.quantityAboveThreshold,
        InventoryHealthStatus.lowStock =>
          InventoryHealthReasonCode.quantityAtOrBelowThreshold,
        InventoryHealthStatus.outOfStock =>
          InventoryHealthReasonCode.quantityIsZero,
      };
  return InventoryHealthResult(
    productId: id,
    productName: name,
    category: category,
    explanation: InventoryHealthExplanation(
      status: status,
      reasonCode: resolvedReason,
      quantity: quantity,
      threshold: threshold,
      unit: unit,
      timestamp: lowStockTestTime,
      summary: 'Health summary',
    ),
  );
}

ConsumptionResult consumptionResult({
  String id = 'rice',
  String name = 'Rice',
  String category = 'Grains',
  double quantity = 10,
  String unit = 'bag',
  double startingQuantity = 20,
  double totalConsumed = 7,
  int consumptionEvents = 2,
  double totalReplenished = 0,
  double totalOtherReduction = 0,
  DateTime? start,
  DateTime? end,
  ConsumptionPattern pattern = ConsumptionPattern.consumptionObserved,
}) {
  final observationStart = start ?? lowStockTestTime;
  final observationEnd = end ?? lowStockTestTime.add(const Duration(days: 14));
  return ConsumptionResult(
    snapshot: ConsumptionSnapshot(
      productId: id,
      productName: name,
      category: category,
      currentQuantity: quantity,
      unit: unit,
      capturedAt: lowStockTestTime,
    ),
    profile: ConsumptionProfile(
      productId: id,
      startingQuantity: startingQuantity,
      currentQuantity: quantity,
      unit: unit,
      events: const [],
      totalConsumed: totalConsumed,
      consumptionEventCount: consumptionEvents,
      totalReplenished: totalReplenished,
      totalNonConsumptionReduction: totalOtherReduction,
      hasInferredStartingBalance: false,
    ),
    explanation: ConsumptionExplanation(
      pattern: pattern,
      reasonCode: consumptionEvents == 0
          ? ConsumptionReasonCode.emptyHistory
          : ConsumptionReasonCode.consumptionEventsObserved,
      eventCount: consumptionEvents,
      consumptionEventCount: consumptionEvents,
      observationPeriod: ConsumptionObservationPeriod(
        start: observationStart,
        end: observationEnd,
      ),
      summary: 'Consumption summary',
    ),
  );
}

LowStockInput lowStockInput({
  InventoryHealthResult? health,
  ConsumptionResult? consumption,
}) =>
    LowStockInput(
      healthResult: health ?? healthResult(),
      consumptionResult: consumption ?? consumptionResult(),
    );
