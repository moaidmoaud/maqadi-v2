import '../domain/consumption_event.dart';
import '../domain/consumption_snapshot.dart';

class ConsumptionInputBatch {
  ConsumptionInputBatch({
    required Iterable<ConsumptionSnapshot> snapshots,
    required Map<String, List<ConsumptionEventInput>> eventsByProduct,
  })  : snapshots = List.unmodifiable(snapshots),
        eventsByProduct = Map.unmodifiable(
          eventsByProduct.map(
            (productId, events) => MapEntry(
              productId,
              List<ConsumptionEventInput>.unmodifiable(events),
            ),
          ),
        );

  final List<ConsumptionSnapshot> snapshots;
  final Map<String, List<ConsumptionEventInput>> eventsByProduct;
}

abstract interface class ConsumptionInputReader {
  Future<ConsumptionInputBatch> read();
}
