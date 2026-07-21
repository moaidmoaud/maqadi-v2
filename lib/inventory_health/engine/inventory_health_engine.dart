import '../domain/inventory_health_result.dart';
import '../domain/inventory_health_snapshot.dart';
import '../domain/inventory_policy.dart';

class InventoryHealthEngine {
  const InventoryHealthEngine();

  InventoryHealthResult evaluate({
    required InventoryHealthSnapshot snapshot,
    required InventoryPolicy? policy,
    required DateTime timestamp,
  }) {
    final invalidSnapshot = snapshot.productId.trim().isEmpty ||
        snapshot.productName.trim().isEmpty ||
        snapshot.unit.trim().isEmpty;
    if (invalidSnapshot) {
      return _result(
        snapshot,
        InventoryHealthStatus.unknown,
        InventoryHealthReasonCode.invalidSnapshot,
        null,
        timestamp,
        'Inventory data is incomplete.',
      );
    }
    if (!snapshot.quantity.isFinite) {
      return _result(
        snapshot,
        InventoryHealthStatus.unknown,
        InventoryHealthReasonCode.invalidQuantity,
        null,
        timestamp,
        'The current quantity is not valid.',
      );
    }
    if (snapshot.quantity < 0) {
      return _result(
        snapshot,
        InventoryHealthStatus.unknown,
        InventoryHealthReasonCode.negativeQuantity,
        null,
        timestamp,
        'The current quantity cannot be negative.',
      );
    }
    if (snapshot.quantity == 0) {
      return _result(
        snapshot,
        InventoryHealthStatus.outOfStock,
        InventoryHealthReasonCode.quantityIsZero,
        null,
        timestamp,
        'No stock is currently available.',
      );
    }
    if (policy == null) {
      return _result(
        snapshot,
        InventoryHealthStatus.unknown,
        InventoryHealthReasonCode.missingPolicy,
        null,
        timestamp,
        'No minimum-stock policy is available.',
      );
    }
    if (policy.productId != snapshot.productId || policy.unit.trim().isEmpty) {
      return _result(
        snapshot,
        InventoryHealthStatus.unknown,
        InventoryHealthReasonCode.invalidPolicy,
        null,
        timestamp,
        'The minimum-stock policy is invalid.',
      );
    }
    if (!policy.lowStockThreshold.isFinite || policy.lowStockThreshold < 0) {
      return _result(
        snapshot,
        InventoryHealthStatus.unknown,
        InventoryHealthReasonCode.invalidThreshold,
        null,
        timestamp,
        'The minimum-stock threshold is invalid.',
      );
    }
    if (policy.unit.trim().toLowerCase() !=
        snapshot.unit.trim().toLowerCase()) {
      return _result(
        snapshot,
        InventoryHealthStatus.unknown,
        InventoryHealthReasonCode.unitMismatch,
        policy.lowStockThreshold,
        timestamp,
        'The quantity and policy units do not match.',
      );
    }
    if (snapshot.quantity <= policy.lowStockThreshold) {
      return _result(
        snapshot,
        InventoryHealthStatus.lowStock,
        InventoryHealthReasonCode.quantityAtOrBelowThreshold,
        policy.lowStockThreshold,
        timestamp,
        'Stock is at or below its configured minimum.',
      );
    }
    return _result(
      snapshot,
      InventoryHealthStatus.healthy,
      InventoryHealthReasonCode.quantityAboveThreshold,
      policy.lowStockThreshold,
      timestamp,
      'Stock is above its configured minimum.',
    );
  }

  InventoryHealthResult _result(
    InventoryHealthSnapshot snapshot,
    InventoryHealthStatus status,
    InventoryHealthReasonCode reasonCode,
    double? threshold,
    DateTime timestamp,
    String summary,
  ) =>
      InventoryHealthResult(
        productId: snapshot.productId,
        productName: snapshot.productName,
        category: snapshot.category,
        explanation: InventoryHealthExplanation(
          status: status,
          reasonCode: reasonCode,
          quantity: snapshot.quantity,
          threshold: threshold,
          unit: snapshot.unit,
          timestamp: timestamp,
          summary: summary,
        ),
      );
}
