import '../domain/consumption_event.dart';
import '../domain/consumption_failure.dart';
import '../domain/consumption_snapshot.dart';

sealed class ConsumptionEventBuildOutcome {
  const ConsumptionEventBuildOutcome();
}

class ConsumptionEventBuildSuccess extends ConsumptionEventBuildOutcome {
  ConsumptionEventBuildSuccess({
    required Iterable<ConsumptionEvent> events,
    required this.startingQuantity,
  }) : events = List.unmodifiable(events);

  final List<ConsumptionEvent> events;
  final double startingQuantity;
}

class ConsumptionEventBuildFailure extends ConsumptionEventBuildOutcome {
  const ConsumptionEventBuildFailure(this.failure);

  final ConsumptionFailure failure;
}

class ConsumptionEventBuilder {
  const ConsumptionEventBuilder();

  ConsumptionEventBuildOutcome build({
    required ConsumptionSnapshot snapshot,
    required List<ConsumptionEventInput> inputs,
  }) {
    if (snapshot.productId.trim().isEmpty ||
        snapshot.productName.trim().isEmpty ||
        snapshot.unit.trim().isEmpty ||
        !snapshot.currentQuantity.isFinite ||
        snapshot.currentQuantity < 0) {
      return _failure(
        snapshot.productId,
        ConsumptionFailureCode.invalidSnapshot,
        'The product consumption snapshot is invalid.',
      );
    }

    var runningQuantity = snapshot.currentQuantity;
    final built = List<ConsumptionEvent?>.filled(inputs.length, null);
    final ids = <String>{};
    for (var index = inputs.length - 1; index >= 0; index--) {
      final input = inputs[index];
      if (input.id.trim().isEmpty ||
          input.productId != snapshot.productId ||
          !input.delta.isFinite) {
        return _failure(
          snapshot.productId,
          ConsumptionFailureCode.invalidEvent,
          'Consumption history contains an invalid event.',
        );
      }
      if (!ids.add(input.id)) {
        return _failure(
          snapshot.productId,
          ConsumptionFailureCode.duplicateEvent,
          'Consumption history contains duplicate event identifiers.',
        );
      }
      final timestamp = input.timestamp;
      if (timestamp == null) {
        return _failure(
          snapshot.productId,
          ConsumptionFailureCode.missingTimestamp,
          'Consumption history contains an event without a timestamp.',
        );
      }
      if (index > 0) {
        final previousTimestamp = inputs[index - 1].timestamp;
        if (previousTimestamp != null &&
            timestamp.isBefore(previousTimestamp)) {
          return _failure(
            snapshot.productId,
            ConsumptionFailureCode.outOfOrderHistory,
            'Consumption history is not in recorded chronological order.',
          );
        }
      }
      if (input.unit.trim().toLowerCase() !=
          snapshot.unit.trim().toLowerCase()) {
        return _failure(
          snapshot.productId,
          ConsumptionFailureCode.unitMismatch,
          'Consumption history contains incompatible quantity units.',
        );
      }

      final previousQuantity = runningQuantity - input.delta;
      if (!previousQuantity.isFinite || previousQuantity < -0.000000001) {
        return _failure(
          snapshot.productId,
          ConsumptionFailureCode.inconsistentHistory,
          'Consumption history cannot be reconciled with current stock.',
        );
      }
      if (input.delta != 0) {
        final reason = _reasonFor(input.movementType);
        built[index] = ConsumptionEvent(
          id: input.id,
          productId: input.productId,
          timestamp: timestamp,
          previousQuantity:
              previousQuantity.abs() < 0.000000001 ? 0 : previousQuantity,
          currentQuantity: runningQuantity,
          delta: input.delta,
          reason: reason,
          source: _sourceFor(reason),
          unit: snapshot.unit,
          sourceReference: input.sourceReference,
        );
      }
      runningQuantity =
          previousQuantity.abs() < 0.000000001 ? 0 : previousQuantity;
    }

    return ConsumptionEventBuildSuccess(
      events: built.whereType<ConsumptionEvent>(),
      startingQuantity: runningQuantity,
    );
  }

  ConsumptionReason _reasonFor(String movementType) {
    return switch (movementType.trim()) {
      'استهلاك' => ConsumptionReason.consumption,
      'شراء' => ConsumptionReason.purchase,
      'إضافة' => ConsumptionReason.stockAddition,
      'تعديل' => ConsumptionReason.manualAdjustment,
      'تعديل دفعة' => ConsumptionReason.batchAdjustment,
      'حذف دفعة' => ConsumptionReason.batchRemoval,
      _ => ConsumptionReason.unknown,
    };
  }

  ConsumptionSource _sourceFor(ConsumptionReason reason) => switch (reason) {
        ConsumptionReason.purchase => ConsumptionSource.purchase,
        ConsumptionReason.batchAdjustment ||
        ConsumptionReason.batchRemoval =>
          ConsumptionSource.batch,
        ConsumptionReason.consumption ||
        ConsumptionReason.manualAdjustment =>
          ConsumptionSource.manual,
        ConsumptionReason.stockAddition => ConsumptionSource.inventory,
        ConsumptionReason.unknown => ConsumptionSource.unknown,
      };

  ConsumptionEventBuildFailure _failure(
    String productId,
    ConsumptionFailureCode code,
    String message,
  ) =>
      ConsumptionEventBuildFailure(
        ConsumptionFailure(
          code: code,
          message: message,
          productId: productId.isEmpty ? null : productId,
        ),
      );
}
