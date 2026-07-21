import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_result.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_snapshot.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_policy.dart';
import 'package:maqadi_v2/inventory_health/engine/inventory_health_engine.dart';

void main() {
  const engine = InventoryHealthEngine();
  final timestamp = DateTime.utc(2026, 7, 21, 12);

  InventoryHealthSnapshot snapshot({
    String id = 'product-1',
    String name = 'Milk',
    String category = 'Dairy',
    double quantity = 5,
    String unit = 'carton',
  }) =>
      InventoryHealthSnapshot(
        productId: id,
        productName: name,
        category: category,
        quantity: quantity,
        unit: unit,
      );

  InventoryPolicy policy({
    String id = 'product-1',
    double threshold = 2,
    String unit = 'carton',
  }) =>
      InventoryPolicy(
        productId: id,
        lowStockThreshold: threshold,
        unit: unit,
      );

  InventoryHealthResult evaluate({
    InventoryHealthSnapshot? input,
    InventoryPolicy? configuredPolicy,
    bool omitPolicy = false,
  }) =>
      engine.evaluate(
        snapshot: input ?? snapshot(),
        policy: omitPolicy ? null : (configuredPolicy ?? policy()),
        timestamp: timestamp,
      );

  group('InventoryHealthEngine decision rules', () {
    test('returns Healthy above the threshold', () {
      expect(evaluate().status, InventoryHealthStatus.healthy);
    });

    test('returns LowStock at the threshold', () {
      expect(
        evaluate(input: snapshot(quantity: 2)).status,
        InventoryHealthStatus.lowStock,
      );
    });

    test('returns LowStock below the threshold', () {
      expect(
        evaluate(input: snapshot(quantity: 1)).status,
        InventoryHealthStatus.lowStock,
      );
    });

    test('returns OutOfStock at zero even without a policy', () {
      expect(
        evaluate(input: snapshot(quantity: 0), omitPolicy: true).status,
        InventoryHealthStatus.outOfStock,
      );
    });

    test('returns Unknown for a missing policy', () {
      final result = evaluate(omitPolicy: true);
      expect(result.status, InventoryHealthStatus.unknown);
      expect(
        result.explanation.reasonCode,
        InventoryHealthReasonCode.missingPolicy,
      );
    });

    test('returns Unknown for a negative threshold', () {
      final result = evaluate(configuredPolicy: policy(threshold: -1));
      expect(result.status, InventoryHealthStatus.unknown);
      expect(
        result.explanation.reasonCode,
        InventoryHealthReasonCode.invalidThreshold,
      );
    });

    test('returns Unknown for a non-finite threshold', () {
      final result = evaluate(configuredPolicy: policy(threshold: double.nan));
      expect(result.status, InventoryHealthStatus.unknown);
      expect(
        result.explanation.reasonCode,
        InventoryHealthReasonCode.invalidThreshold,
      );
    });

    test('returns Unknown for a negative quantity', () {
      final result = evaluate(input: snapshot(quantity: -1));
      expect(result.status, InventoryHealthStatus.unknown);
      expect(
        result.explanation.reasonCode,
        InventoryHealthReasonCode.negativeQuantity,
      );
    });

    test('returns Unknown for a non-finite quantity', () {
      final result = evaluate(input: snapshot(quantity: double.infinity));
      expect(result.status, InventoryHealthStatus.unknown);
      expect(
        result.explanation.reasonCode,
        InventoryHealthReasonCode.invalidQuantity,
      );
    });

    test('returns Unknown for an empty product id', () {
      expect(
        evaluate(input: snapshot(id: '')).status,
        InventoryHealthStatus.unknown,
      );
    });

    test('returns Unknown for an empty product name', () {
      expect(
        evaluate(input: snapshot(name: '')).status,
        InventoryHealthStatus.unknown,
      );
    });

    test('returns Unknown for an empty snapshot unit', () {
      expect(
        evaluate(input: snapshot(unit: '')).status,
        InventoryHealthStatus.unknown,
      );
    });

    test('returns Unknown for mismatched units', () {
      final result = evaluate(configuredPolicy: policy(unit: 'piece'));
      expect(result.status, InventoryHealthStatus.unknown);
      expect(
        result.explanation.reasonCode,
        InventoryHealthReasonCode.unitMismatch,
      );
    });

    test('matches units without case or surrounding whitespace', () {
      final result = evaluate(
        input: snapshot(unit: ' Carton '),
        configuredPolicy: policy(unit: 'carton'),
      );
      expect(result.status, InventoryHealthStatus.healthy);
    });

    test('returns Unknown for a policy belonging to another product', () {
      final result = evaluate(configuredPolicy: policy(id: 'product-2'));
      expect(result.status, InventoryHealthStatus.unknown);
      expect(
        result.explanation.reasonCode,
        InventoryHealthReasonCode.invalidPolicy,
      );
    });

    test('zero threshold classifies a positive quantity as Healthy', () {
      expect(
        evaluate(configuredPolicy: policy(threshold: 0)).status,
        InventoryHealthStatus.healthy,
      );
    });
  });

  group('InventoryHealthExplanation', () {
    test('contains every required decision field', () {
      final explanation = evaluate().explanation;
      expect(explanation.status, InventoryHealthStatus.healthy);
      expect(
        explanation.reasonCode,
        InventoryHealthReasonCode.quantityAboveThreshold,
      );
      expect(explanation.quantity, 5);
      expect(explanation.threshold, 2);
      expect(explanation.unit, 'carton');
      expect(explanation.timestamp, timestamp);
      expect(explanation.summary, isNotEmpty);
    });

    test('uses the zero-quantity reason code', () {
      expect(
        evaluate(input: snapshot(quantity: 0)).explanation.reasonCode,
        InventoryHealthReasonCode.quantityIsZero,
      );
    });

    test('uses the low-stock reason code', () {
      expect(
        evaluate(input: snapshot(quantity: 2)).explanation.reasonCode,
        InventoryHealthReasonCode.quantityAtOrBelowThreshold,
      );
    });

    test('is deterministic for identical inputs and timestamp', () {
      final first = evaluate();
      final second = evaluate();
      expect(second.status, first.status);
      expect(second.explanation.reasonCode, first.explanation.reasonCode);
      expect(second.explanation.quantity, first.explanation.quantity);
      expect(second.explanation.threshold, first.explanation.threshold);
      expect(second.explanation.timestamp, first.explanation.timestamp);
      expect(second.explanation.summary, first.explanation.summary);
    });
  });
}
