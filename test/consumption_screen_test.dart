import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/consumption/application/consumption_input_reader.dart';
import 'package:maqadi_v2/consumption/application/consumption_service.dart';
import 'package:maqadi_v2/consumption/domain/consumption_event.dart';
import 'package:maqadi_v2/consumption/domain/consumption_snapshot.dart';
import 'package:maqadi_v2/consumption/presentation/consumption_screen.dart';

void main() {
  Widget app(ConsumptionInputReader reader) => MaterialApp(
        home: ConsumptionScreen(
          service: ConsumptionService(inputReader: reader),
        ),
      );

  group('ConsumptionScreen', () {
    testWidgets('shows loading then a history summary', (tester) async {
      final completer = Completer<ConsumptionInputBatch>();
      await tester.pumpWidget(app(_CompleterReader(completer)));
      expect(find.byKey(const ValueKey('consumption-loading')), findsOneWidget);
      completer.complete(_batch());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('consumption-summary')), findsOneWidget);
      expect(find.text('Observed consumption'), findsOneWidget);
      expect(find.byKey(const ValueKey('consumption-event-rice-use')),
          findsOneWidget);
    });

    testWidgets('shows an empty inventory state', (tester) async {
      await tester.pumpWidget(
        app(_Reader(ConsumptionInputBatch(snapshots: [], eventsByProduct: {}))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('consumption-empty')), findsOneWidget);
    });

    testWidgets('shows reader failures and retries', (tester) async {
      final reader = _RetryReader(_batch());
      await tester.pumpWidget(app(reader));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('consumption-error')), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('consumption-summary')), findsOneWidget);
      expect(reader.readCount, 2);
    });

    testWidgets('displays the engine-provided explanation', (tester) async {
      await tester.pumpWidget(app(_Reader(_batch())));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('consumption-explanation')));
      await tester.pumpAndSettle();
      expect(find.text('Consumption explanation'), findsWidgets);
      expect(find.text('consumptionWithInventoryChanges'), findsOneWidget);
      expect(
        find.text(
            'Consumption was observed alongside other inventory changes.'),
        findsOneWidget,
      );
    });

    testWidgets('selects another product without re-reading inventory',
        (tester) async {
      final reader = _Reader(_batch());
      await tester.pumpWidget(app(reader));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('consumption-product-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milk').last);
      await tester.pumpAndSettle();
      expect(find.text('No quantity-change history'), findsOneWidget);
      expect(reader.readCount, 1);
    });

    testWidgets('shows a no-history state for an untouched product',
        (tester) async {
      final batch = ConsumptionInputBatch(
        snapshots: [_milkSnapshot()],
        eventsByProduct: const {},
      );
      await tester.pumpWidget(app(_Reader(batch)));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('consumption-no-history')), findsOneWidget);
      expect(find.text('No history'), findsOneWidget);
    });
  });
}

ConsumptionInputBatch _batch() => ConsumptionInputBatch(
      snapshots: [_riceSnapshot(), _milkSnapshot()],
      eventsByProduct: {
        'rice': [
          ConsumptionEventInput(
            id: 'rice-add',
            productId: 'rice',
            timestamp: DateTime.utc(2026, 7, 20),
            delta: 5,
            unit: 'bag',
            movementType: 'شراء',
          ),
          ConsumptionEventInput(
            id: 'rice-use',
            productId: 'rice',
            timestamp: DateTime.utc(2026, 7, 21),
            delta: -1,
            unit: 'bag',
            movementType: 'استهلاك',
          ),
        ],
      },
    );

ConsumptionSnapshot _riceSnapshot() => ConsumptionSnapshot(
      productId: 'rice',
      productName: 'Rice',
      category: 'Grains',
      currentQuantity: 4,
      unit: 'bag',
      capturedAt: DateTime.utc(2026, 7, 22),
    );

ConsumptionSnapshot _milkSnapshot() => ConsumptionSnapshot(
      productId: 'milk',
      productName: 'Milk',
      category: 'Dairy',
      currentQuantity: 2,
      unit: 'carton',
      capturedAt: DateTime.utc(2026, 7, 22),
    );

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

class _CompleterReader implements ConsumptionInputReader {
  _CompleterReader(this.completer);

  final Completer<ConsumptionInputBatch> completer;

  @override
  Future<ConsumptionInputBatch> read() => completer.future;
}

class _RetryReader implements ConsumptionInputReader {
  _RetryReader(this.batch);

  final ConsumptionInputBatch batch;
  int readCount = 0;

  @override
  Future<ConsumptionInputBatch> read() async {
    readCount++;
    if (readCount == 1) throw StateError('unavailable');
    return batch;
  }
}
