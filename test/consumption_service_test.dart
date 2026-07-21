import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/consumption/application/consumption_input_reader.dart';
import 'package:maqadi_v2/consumption/application/consumption_service.dart';
import 'package:maqadi_v2/consumption/domain/consumption_event.dart';
import 'package:maqadi_v2/consumption/domain/consumption_failure.dart';
import 'package:maqadi_v2/consumption/domain/consumption_result.dart';
import 'package:maqadi_v2/consumption/domain/consumption_snapshot.dart';
import 'package:maqadi_v2/consumption/engine/consumption_engine.dart';
import 'package:maqadi_v2/consumption/infrastructure/inventory_service_consumption_reader.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

void main() {
  final capturedAt = DateTime.utc(2026, 7, 22, 12);

  ConsumptionSnapshot snapshot(String id, {double quantity = 0}) =>
      ConsumptionSnapshot(
        productId: id,
        productName: 'Product $id',
        category: 'Category',
        currentQuantity: quantity,
        unit: 'piece',
        capturedAt: capturedAt,
      );

  group('ConsumptionService', () {
    test('reads the complete input exactly once', () async {
      final reader = _Reader(
        ConsumptionInputBatch(
          snapshots: [snapshot('one')],
          eventsByProduct: const {},
        ),
      );
      await ConsumptionService(inputReader: reader).evaluateInventory();
      expect(reader.readCount, 1);
    });

    test('invokes the engine once per product', () async {
      final engine = _CountingEngine();
      final reader = _Reader(
        ConsumptionInputBatch(
          snapshots: [snapshot('one'), snapshot('two')],
          eventsByProduct: const {},
        ),
      );
      await ConsumptionService(
        inputReader: reader,
        engine: engine,
      ).evaluateInventory();
      expect(engine.evaluationCount, 2);
    });

    test('rejects duplicate product identifiers', () async {
      final result = await ConsumptionService(
        inputReader: _Reader(
          ConsumptionInputBatch(
            snapshots: [snapshot('one'), snapshot('one')],
            eventsByProduct: const {},
          ),
        ),
      ).evaluateInventory() as ConsumptionEvaluationFailure;
      expect(result.failure.code, ConsumptionFailureCode.duplicateProductId);
    });

    test('maps reader exceptions to an input failure', () async {
      final result = await ConsumptionService(
        inputReader: _ThrowingReader(),
      ).evaluateInventory() as ConsumptionEvaluationFailure;
      expect(result.failure.code, ConsumptionFailureCode.inputUnavailable);
    });

    test('keeps invalid product history as an item failure', () async {
      final result = await ConsumptionService(
        inputReader: _Reader(
          ConsumptionInputBatch(
            snapshots: [snapshot('one', quantity: 1)],
            eventsByProduct: {
              'one': [
                ConsumptionEventInput(
                  id: 'bad',
                  productId: 'one',
                  timestamp: capturedAt,
                  delta: -1,
                  unit: 'kg',
                  movementType: 'استهلاك',
                ),
              ],
            },
          ),
        ),
      ).evaluateInventory() as ConsumptionEvaluationSuccess;
      expect(result.results, isEmpty);
      expect(
        result.failures['one']?.code,
        ConsumptionFailureCode.unitMismatch,
      );
    });

    test('maps unexpected engine exceptions to an evaluation failure',
        () async {
      final result = await ConsumptionService(
        inputReader: _Reader(
          ConsumptionInputBatch(
            snapshots: [snapshot('one')],
            eventsByProduct: const {},
          ),
        ),
        engine: _ThrowingEngine(),
      ).evaluateInventory() as ConsumptionEvaluationFailure;
      expect(result.failure.code, ConsumptionFailureCode.evaluationFailed);
    });

    test('evaluates a large movement history', () async {
      final events = [
        for (var index = 0; index < 10000; index++)
          ConsumptionEventInput(
            id: 'event-$index',
            productId: 'one',
            timestamp: capturedAt,
            delta: -1,
            unit: 'piece',
            movementType: 'استهلاك',
          ),
      ];
      final result = await ConsumptionService(
        inputReader: _Reader(
          ConsumptionInputBatch(
            snapshots: [snapshot('one')],
            eventsByProduct: {'one': events},
          ),
        ),
      ).evaluateInventory() as ConsumptionEvaluationSuccess;
      expect(result.results.single.profile.events, hasLength(10000));
      expect(result.results.single.profile.totalConsumed, 10000);
    });
  });

  test('InventoryService reader scans loaded history without writing',
      () async {
    final item = PantryItem(
      id: 'rice',
      name: 'Rice',
      category: 'Grains',
      minimum: 1,
      unit: 'bag',
      location: 'Pantry',
      quantity: 4,
    );
    final movements = [
      PantryMovement(
        id: 'add',
        pantryItemId: 'rice',
        productName: 'Rice',
        type: 'إضافة',
        amount: 5,
        unit: 'bag',
        createdAt: DateTime.utc(2026, 7, 20),
      ),
      PantryMovement(
        id: 'consume',
        pantryItemId: 'rice',
        productName: 'Rice',
        type: 'استهلاك',
        amount: -1,
        unit: 'bag',
        createdAt: DateTime.utc(2026, 7, 21),
      ),
      PantryMovement(
        id: 'orphan',
        pantryItemId: 'deleted',
        productName: 'Deleted',
        type: 'استهلاك',
        amount: -1,
        unit: 'piece',
        createdAt: DateTime.utc(2026, 7, 21),
      ),
    ];
    final inventory = InventoryService(items: [item], movements: movements);
    final batch = await InventoryServiceConsumptionReader(
      inventory,
      clock: () => capturedAt,
    ).read();
    expect(batch.snapshots.single.currentQuantity, 4);
    expect(batch.snapshots.single.capturedAt, capturedAt);
    expect(batch.eventsByProduct['rice'], hasLength(2));
    expect(batch.eventsByProduct, isNot(contains('deleted')));
    expect(inventory.items.single.quantity, 4);
    expect(inventory.movements, hasLength(3));
  });
}

class _Reader implements ConsumptionInputReader {
  _Reader(this.batch);

  final ConsumptionInputBatch batch;
  int readCount = 0;

  @override
  Future<ConsumptionInputBatch> read() async {
    readCount++;
    return batch;
  }
}

class _ThrowingReader implements ConsumptionInputReader {
  @override
  Future<ConsumptionInputBatch> read() => throw StateError('unavailable');
}

class _CountingEngine extends ConsumptionEngine {
  int evaluationCount = 0;

  @override
  ConsumptionItemEvaluation evaluate({
    required ConsumptionSnapshot snapshot,
    required List<ConsumptionEventInput> inputs,
  }) {
    evaluationCount++;
    return super.evaluate(snapshot: snapshot, inputs: inputs);
  }
}

class _ThrowingEngine extends ConsumptionEngine {
  @override
  ConsumptionItemEvaluation evaluate({
    required ConsumptionSnapshot snapshot,
    required List<ConsumptionEventInput> inputs,
  }) =>
      throw StateError('engine failure');
}
