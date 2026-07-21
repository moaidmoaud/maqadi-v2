import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/consumption/domain/consumption_event.dart';
import 'package:maqadi_v2/consumption/domain/consumption_profile.dart';
import 'package:maqadi_v2/consumption/domain/consumption_result.dart';
import 'package:maqadi_v2/consumption/domain/consumption_snapshot.dart';
import 'package:maqadi_v2/consumption/engine/consumption_engine.dart';

void main() {
  const engine = ConsumptionEngine();
  final now = DateTime.utc(2026, 7, 22);
  final snapshot = ConsumptionSnapshot(
    productId: 'rice',
    productName: 'Rice',
    category: 'Grains',
    currentQuantity: 4,
    unit: 'bag',
    capturedAt: now,
  );

  ConsumptionEventInput event(
    String id,
    double delta,
    String type, {
    int day = 20,
  }) =>
      ConsumptionEventInput(
        id: id,
        productId: 'rice',
        timestamp: DateTime.utc(2026, 7, day),
        delta: delta,
        unit: 'bag',
        movementType: type,
      );

  ConsumptionResult evaluate(List<ConsumptionEventInput> inputs) =>
      (engine.evaluate(snapshot: snapshot, inputs: inputs)
              as ConsumptionItemSuccess)
          .result;

  group('ConsumptionEngine', () {
    test('returns a no-history profile', () {
      final result = evaluate(const []);
      expect(result.explanation.pattern, ConsumptionPattern.noHistory);
      expect(result.profile.totalConsumed, 0);
    });

    test('does not count a purchase as consumption', () {
      final result = evaluate([event('purchase', 4, 'شراء')]);
      expect(
        result.explanation.pattern,
        ConsumptionPattern.noObservedConsumption,
      );
      expect(result.profile.totalConsumed, 0);
      expect(result.profile.totalReplenished, 4);
    });

    test('classifies non-consumption reductions as adjustments only', () {
      final result = evaluate([event('adjust', -2, 'تعديل')]);
      expect(result.explanation.pattern, ConsumptionPattern.adjustmentOnly);
      expect(result.profile.totalNonConsumptionReduction, 2);
    });

    test('classifies consumption-only history', () {
      final result = evaluate([event('consume', -2, 'استهلاك')]);
      expect(
        result.explanation.pattern,
        ConsumptionPattern.consumptionObserved,
      );
      expect(result.profile.totalConsumed, 2);
      expect(result.profile.consumptionEventCount, 1);
    });

    test('classifies consumption alongside other stock changes', () {
      final result = evaluate([
        event('purchase', 2, 'شراء'),
        event('consume', -2, 'استهلاك', day: 21),
      ]);
      expect(
        result.explanation.pattern,
        ConsumptionPattern.consumptionWithOtherChanges,
      );
    });

    test('does not count batch removal as consumption', () {
      final result = evaluate([event('remove', -2, 'حذف دفعة')]);
      expect(result.profile.totalConsumed, 0);
      expect(result.profile.totalNonConsumptionReduction, 2);
    });

    test('totals multiple consumption events', () {
      final result = evaluate([
        event('consume-1', -1, 'استهلاك'),
        event('consume-2', -2, 'استهلاك', day: 21),
      ]);
      expect(result.profile.totalConsumed, 3);
      expect(result.profile.consumptionEventCount, 2);
    });

    test('generates every required explanation field', () {
      final result = evaluate([event('consume', -2, 'استهلاك')]);
      final explanation = result.explanation;
      expect(explanation.reasonCode,
          ConsumptionReasonCode.consumptionEventsObserved);
      expect(explanation.eventCount, 1);
      expect(explanation.consumptionEventCount, 1);
      expect(explanation.observationPeriod.start, DateTime.utc(2026, 7, 20));
      expect(explanation.observationPeriod.end, DateTime.utc(2026, 7, 20));
      expect(explanation.summary, isNotEmpty);
    });

    test('marks a non-zero reconstructed baseline as inferred', () {
      final result = evaluate([event('consume', -2, 'استهلاك')]);
      expect(result.profile.startingQuantity, 6);
      expect(result.profile.hasInferredStartingBalance, isTrue);
    });
  });
}
