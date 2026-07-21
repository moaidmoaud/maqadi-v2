import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_input_reader.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_service.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_failure.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_result.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_snapshot.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_policy.dart';
import 'package:maqadi_v2/inventory_health/engine/inventory_health_engine.dart';
import 'package:maqadi_v2/inventory_health/infrastructure/inventory_service_health_reader.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

void main() {
  final timestamp = DateTime.utc(2026, 7, 21, 14);

  InventoryHealthSnapshot snapshot(String id, double quantity) =>
      InventoryHealthSnapshot(
        productId: id,
        productName: 'Product $id',
        category: 'Category',
        quantity: quantity,
        unit: 'piece',
      );

  InventoryPolicy policy(String id, [double threshold = 1]) => InventoryPolicy(
        productId: id,
        lowStockThreshold: threshold,
        unit: 'piece',
      );

  InventoryHealthService serviceFor(
    InventoryHealthInputReader reader, {
    InventoryHealthEngine engine = const InventoryHealthEngine(),
  }) =>
      InventoryHealthService(
        inputReader: reader,
        engine: engine,
        clock: () => timestamp,
      );

  group('InventoryHealthService', () {
    test('reads inventory exactly once per evaluation', () async {
      final reader = _FakeReader(
        InventoryHealthInputBatch(
          snapshots: [snapshot('1', 3)],
          policies: [policy('1')],
        ),
      );
      await serviceFor(reader).evaluateInventory();
      expect(reader.readCount, 1);
    });

    test('invokes the engine once per item', () async {
      final engine = _CountingEngine();
      final reader = _FakeReader(
        InventoryHealthInputBatch(
          snapshots: [snapshot('1', 0), snapshot('2', 1), snapshot('3', 2)],
          policies: [policy('1'), policy('2'), policy('3')],
        ),
      );
      await serviceFor(reader, engine: engine).evaluateInventory();
      expect(engine.evaluationCount, 3);
    });

    test('uses one timestamp for the entire batch', () async {
      final result = await serviceFor(
        _FakeReader(
          InventoryHealthInputBatch(
            snapshots: [snapshot('1', 1), snapshot('2', 2)],
            policies: [policy('1'), policy('2')],
          ),
        ),
      ).evaluateInventory() as InventoryHealthEvaluationSuccess;
      expect(
        result.results.map((item) => item.explanation.timestamp).toSet(),
        {timestamp},
      );
    });

    test('sorts by urgency then product name', () async {
      final input = InventoryHealthInputBatch(
        snapshots: [
          snapshot('healthy', 3),
          snapshot('low-b', 1),
          snapshot('out', 0),
          snapshot('low-a', 1),
        ],
        policies: [
          policy('healthy'),
          policy('low-b'),
          policy('out'),
          policy('low-a'),
        ],
      );
      final result = await serviceFor(
        _FakeReader(input),
      ).evaluateInventory() as InventoryHealthEvaluationSuccess;
      expect(
        result.results.map((item) => item.productId),
        ['out', 'low-a', 'low-b', 'healthy'],
      );
    });

    test('returns an empty success for empty inventory', () async {
      final result = await serviceFor(
        _FakeReader(InventoryHealthInputBatch(snapshots: [], policies: [])),
      ).evaluateInventory();
      expect(result, isA<InventoryHealthEvaluationSuccess>());
      expect((result as InventoryHealthEvaluationSuccess).results, isEmpty);
    });

    test('maps input reader exceptions to an explicit failure', () async {
      final result = await serviceFor(_ThrowingReader()).evaluateInventory();
      expect(
        (result as InventoryHealthEvaluationFailure).failure.code,
        InventoryHealthFailureCode.inputUnavailable,
      );
    });

    test('rejects duplicate product identifiers', () async {
      final result = await serviceFor(
        _FakeReader(
          InventoryHealthInputBatch(
            snapshots: [snapshot('1', 1), snapshot('1', 2)],
            policies: [policy('1')],
          ),
        ),
      ).evaluateInventory();
      expect(
        (result as InventoryHealthEvaluationFailure).failure.code,
        InventoryHealthFailureCode.duplicateProductId,
      );
    });

    test('rejects duplicate policies', () async {
      final result = await serviceFor(
        _FakeReader(
          InventoryHealthInputBatch(
            snapshots: [snapshot('1', 1)],
            policies: [policy('1'), policy('1', 2)],
          ),
        ),
      ).evaluateInventory();
      expect(
        (result as InventoryHealthEvaluationFailure).failure.code,
        InventoryHealthFailureCode.duplicatePolicy,
      );
    });

    test('maps engine exceptions to an explicit failure', () async {
      final result = await serviceFor(
        _FakeReader(
          InventoryHealthInputBatch(
            snapshots: [snapshot('1', 1)],
            policies: [policy('1')],
          ),
        ),
        engine: _ThrowingEngine(),
      ).evaluateInventory();
      expect(
        (result as InventoryHealthEvaluationFailure).failure.code,
        InventoryHealthFailureCode.evaluationFailed,
      );
    });

    test('evaluates a large inventory batch in one read', () async {
      final snapshots = [
        for (var index = 0; index < 10000; index++) snapshot('$index', 2)
      ];
      final policies = [
        for (var index = 0; index < 10000; index++) policy('$index')
      ];
      final reader = _FakeReader(
        InventoryHealthInputBatch(snapshots: snapshots, policies: policies),
      );
      final result = await serviceFor(reader).evaluateInventory();
      expect((result as InventoryHealthEvaluationSuccess).results,
          hasLength(10000));
      expect(reader.readCount, 1);
    });
  });

  group('InventoryServiceHealthReader', () {
    test('captures loaded inventory without changing it', () async {
      final item = PantryItem(
        id: 'milk',
        name: 'Milk',
        category: 'Dairy',
        minimum: 2,
        unit: 'carton',
        location: 'Pantry',
        quantity: 4,
      );
      final inventory = InventoryService(items: [item]);
      final batch = await InventoryServiceHealthReader(inventory).read();
      expect(batch.snapshots.single.quantity, 4);
      expect(batch.policies.single.lowStockThreshold, 2);
      expect(inventory.items.single.quantity, 4);
      expect(inventory.movements, isEmpty);
    });

    test('returns unmodifiable input collections', () async {
      final batch = await InventoryServiceHealthReader(
        InventoryService(),
      ).read();
      expect(
          () => batch.snapshots.add(snapshot('x', 1)), throwsUnsupportedError);
      expect(() => batch.policies.add(policy('x')), throwsUnsupportedError);
    });
  });
}

class _FakeReader implements InventoryHealthInputReader {
  _FakeReader(this.batch);

  final InventoryHealthInputBatch batch;
  int readCount = 0;

  @override
  Future<InventoryHealthInputBatch> read() async {
    readCount++;
    return batch;
  }
}

class _ThrowingReader implements InventoryHealthInputReader {
  @override
  Future<InventoryHealthInputBatch> read() => throw StateError('unavailable');
}

class _CountingEngine extends InventoryHealthEngine {
  int evaluationCount = 0;

  @override
  InventoryHealthResult evaluate({
    required InventoryHealthSnapshot snapshot,
    required InventoryPolicy? policy,
    required DateTime timestamp,
  }) {
    evaluationCount++;
    return super
        .evaluate(snapshot: snapshot, policy: policy, timestamp: timestamp);
  }
}

class _ThrowingEngine extends InventoryHealthEngine {
  @override
  InventoryHealthResult evaluate({
    required InventoryHealthSnapshot snapshot,
    required InventoryPolicy? policy,
    required DateTime timestamp,
  }) =>
      throw StateError('engine failure');
}
