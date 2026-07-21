import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/consumption/domain/consumption_event.dart';
import 'package:maqadi_v2/consumption/domain/consumption_failure.dart';
import 'package:maqadi_v2/consumption/domain/consumption_snapshot.dart';
import 'package:maqadi_v2/consumption/engine/consumption_event_builder.dart';

void main() {
  const builder = ConsumptionEventBuilder();
  final capturedAt = DateTime.utc(2026, 7, 22, 12);

  ConsumptionSnapshot snapshot({
    String id = 'rice',
    String name = 'Rice',
    double quantity = 6,
    String unit = 'bag',
  }) =>
      ConsumptionSnapshot(
        productId: id,
        productName: name,
        category: 'Grains',
        currentQuantity: quantity,
        unit: unit,
        capturedAt: capturedAt,
      );

  ConsumptionEventInput input({
    String id = 'event-1',
    String productId = 'rice',
    DateTime? timestamp,
    double delta = -2,
    String unit = 'bag',
    String type = 'استهلاك',
  }) =>
      ConsumptionEventInput(
        id: id,
        productId: productId,
        timestamp: timestamp ?? DateTime.utc(2026, 7, 20),
        delta: delta,
        unit: unit,
        movementType: type,
      );

  group('ConsumptionEventBuilder', () {
    test('returns current quantity as the baseline for empty history', () {
      final result = builder.build(snapshot: snapshot(), inputs: const [])
          as ConsumptionEventBuildSuccess;
      expect(result.events, isEmpty);
      expect(result.startingQuantity, 6);
    });

    test('reconstructs previous and current quantities in one reverse pass',
        () {
      final result = builder.build(
        snapshot: snapshot(quantity: 6),
        inputs: [
          input(id: 'add', delta: 10, type: 'إضافة'),
          input(
            id: 'consume',
            delta: -4,
            timestamp: DateTime.utc(2026, 7, 21),
          ),
        ],
      ) as ConsumptionEventBuildSuccess;
      expect(result.startingQuantity, 0);
      expect(result.events.first.previousQuantity, 0);
      expect(result.events.first.currentQuantity, 10);
      expect(result.events.last.previousQuantity, 10);
      expect(result.events.last.currentQuantity, 6);
    });

    test('ignores zero-delta metadata events', () {
      final result = builder.build(
        snapshot: snapshot(),
        inputs: [input(delta: 0, type: 'تحديث بيانات')],
      ) as ConsumptionEventBuildSuccess;
      expect(result.events, isEmpty);
      expect(result.startingQuantity, 6);
    });

    test('accepts duplicate timestamps in recorded order', () {
      final timestamp = DateTime.utc(2026, 7, 20);
      final result = builder.build(
        snapshot: snapshot(quantity: 2),
        inputs: [
          input(id: 'one', delta: 3, timestamp: timestamp),
          input(id: 'two', delta: -1, timestamp: timestamp),
        ],
      );
      expect(result, isA<ConsumptionEventBuildSuccess>());
    });

    test('rejects a missing timestamp', () {
      final event = ConsumptionEventInput(
        id: 'event',
        productId: 'rice',
        timestamp: null,
        delta: -1,
        unit: 'bag',
        movementType: 'استهلاك',
      );
      final result = builder.build(snapshot: snapshot(), inputs: [event])
          as ConsumptionEventBuildFailure;
      expect(result.failure.code, ConsumptionFailureCode.missingTimestamp);
    });

    test('rejects out-of-order timestamps without sorting', () {
      final result = builder.build(
        snapshot: snapshot(),
        inputs: [
          input(timestamp: DateTime.utc(2026, 7, 21)),
          input(id: 'event-2', timestamp: DateTime.utc(2026, 7, 20)),
        ],
      ) as ConsumptionEventBuildFailure;
      expect(result.failure.code, ConsumptionFailureCode.outOfOrderHistory);
    });

    test('rejects duplicate event identifiers', () {
      final result = builder.build(
        snapshot: snapshot(),
        inputs: [input(), input(timestamp: DateTime.utc(2026, 7, 21))],
      ) as ConsumptionEventBuildFailure;
      expect(result.failure.code, ConsumptionFailureCode.duplicateEvent);
    });

    test('rejects incompatible units', () {
      final result = builder.build(
        snapshot: snapshot(),
        inputs: [input(unit: 'kg')],
      ) as ConsumptionEventBuildFailure;
      expect(result.failure.code, ConsumptionFailureCode.unitMismatch);
    });

    test('rejects an event belonging to another product', () {
      final result = builder.build(
        snapshot: snapshot(),
        inputs: [input(productId: 'milk')],
      ) as ConsumptionEventBuildFailure;
      expect(result.failure.code, ConsumptionFailureCode.invalidEvent);
    });

    test('rejects an invalid product snapshot', () {
      final result = builder.build(
        snapshot: snapshot(id: ''),
        inputs: const [],
      ) as ConsumptionEventBuildFailure;
      expect(result.failure.code, ConsumptionFailureCode.invalidSnapshot);
    });

    test('rejects history inconsistent with current quantity', () {
      final result = builder.build(
        snapshot: snapshot(quantity: 2),
        inputs: [input(delta: 5, type: 'إضافة')],
      ) as ConsumptionEventBuildFailure;
      expect(result.failure.code, ConsumptionFailureCode.inconsistentHistory);
    });

    test('normalizes every supported movement type and source', () {
      const expectations = {
        'استهلاك': ConsumptionReason.consumption,
        'شراء': ConsumptionReason.purchase,
        'إضافة': ConsumptionReason.stockAddition,
        'تعديل': ConsumptionReason.manualAdjustment,
        'تعديل دفعة': ConsumptionReason.batchAdjustment,
        'حذف دفعة': ConsumptionReason.batchRemoval,
      };
      for (final entry in expectations.entries) {
        final result = builder.build(
          snapshot: snapshot(quantity: entry.key == 'حذف دفعة' ? 0 : 1),
          inputs: [
            input(
              delta: entry.key == 'حذف دفعة' || entry.key == 'استهلاك' ? -1 : 1,
              type: entry.key,
            ),
          ],
        ) as ConsumptionEventBuildSuccess;
        expect(result.events.single.reason, entry.value);
      }
    });

    test('preserves unknown movement types without counting them implicitly',
        () {
      final result = builder.build(
        snapshot: snapshot(quantity: 4),
        inputs: [input(delta: -2, type: 'legacy')],
      ) as ConsumptionEventBuildSuccess;
      expect(result.events.single.reason, ConsumptionReason.unknown);
      expect(result.events.single.source, ConsumptionSource.unknown);
    });

    test('is deterministic for identical snapshots and inputs', () {
      final inputs = [input()];
      final first = builder.build(snapshot: snapshot(), inputs: inputs)
          as ConsumptionEventBuildSuccess;
      final second = builder.build(snapshot: snapshot(), inputs: inputs)
          as ConsumptionEventBuildSuccess;
      expect(second.startingQuantity, first.startingQuantity);
      expect(second.events.single.delta, first.events.single.delta);
      expect(
        second.events.single.previousQuantity,
        first.events.single.previousQuantity,
      );
    });
  });
}
