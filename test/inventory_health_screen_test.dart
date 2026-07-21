import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_input_reader.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_service.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_snapshot.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_policy.dart';
import 'package:maqadi_v2/inventory_health/presentation/inventory_health_screen.dart';

void main() {
  final timestamp = DateTime.utc(2026, 7, 21, 16);

  InventoryHealthService service(
    InventoryHealthInputReader reader,
  ) =>
      InventoryHealthService(inputReader: reader, clock: () => timestamp);

  Widget app(
    InventoryHealthService healthService, {
    InventoryHealthProductOpener? onOpenProduct,
  }) =>
      MaterialApp(
        home: InventoryHealthScreen(
          service: healthService,
          onOpenProduct: onOpenProduct ?? (_) async {},
        ),
      );

  group('InventoryHealthScreen', () {
    testWidgets('shows loading then ranked results', (tester) async {
      final completer = Completer<InventoryHealthInputBatch>();
      await tester.pumpWidget(app(service(_CompleterReader(completer))));
      expect(find.byKey(const ValueKey('inventory-health-loading')),
          findsOneWidget);
      completer.complete(_batch());
      await tester.pumpAndSettle();
      expect(find.text('Out of stock'), findsWidgets);
      expect(find.text('Low stock'), findsWidgets);
      expect(find.text('Healthy'), findsWidgets);
    });

    testWidgets('shows an empty state', (tester) async {
      await tester.pumpWidget(
        app(
          service(
            _Reader(InventoryHealthInputBatch(snapshots: [], policies: [])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('inventory-health-empty')), findsOneWidget);
    });

    testWidgets('shows an error and retries through the service',
        (tester) async {
      final reader = _RetryReader(_batch());
      await tester.pumpWidget(app(service(reader)));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('inventory-health-error')), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('inventory-health-error')), findsNothing);
      expect(find.text('Milk'), findsOneWidget);
      expect(reader.readCount, 2);
    });

    testWidgets('filters results by the selected health state', (tester) async {
      await tester.pumpWidget(app(service(_Reader(_batch()))));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('inventory-health-filter-lowStock')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
      expect(find.text('Milk'), findsNothing);
      expect(find.text('Water'), findsNothing);
    });

    testWidgets('shows the engine-provided explanation', (tester) async {
      await tester.pumpWidget(app(service(_Reader(_batch()))));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('inventory-health-explanation-rice')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Health explanation'), findsOneWidget);
      expect(find.text('quantityAtOrBelowThreshold'), findsOneWidget);
      expect(find.text('Stock is at or below its configured minimum.'),
          findsOneWidget);
    });

    testWidgets('opens the selected product and refreshes afterward',
        (tester) async {
      String? openedProductId;
      final reader = _Reader(_batch());
      await tester.pumpWidget(
        app(
          service(reader),
          onOpenProduct: (productId) async => openedProductId = productId,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('inventory-health-product-milk')),
      );
      await tester.pumpAndSettle();
      expect(openedProductId, 'milk');
      expect(reader.readCount, 2);
    });
  });
}

InventoryHealthInputBatch _batch() => InventoryHealthInputBatch(
      snapshots: const [
        InventoryHealthSnapshot(
          productId: 'milk',
          productName: 'Milk',
          category: 'Dairy',
          quantity: 3,
          unit: 'carton',
        ),
        InventoryHealthSnapshot(
          productId: 'rice',
          productName: 'Rice',
          category: 'Grains',
          quantity: 1,
          unit: 'bag',
        ),
        InventoryHealthSnapshot(
          productId: 'water',
          productName: 'Water',
          category: 'Drinks',
          quantity: 0,
          unit: 'bottle',
        ),
      ],
      policies: const [
        InventoryPolicy(
          productId: 'milk',
          lowStockThreshold: 1,
          unit: 'carton',
        ),
        InventoryPolicy(
          productId: 'rice',
          lowStockThreshold: 1,
          unit: 'bag',
        ),
        InventoryPolicy(
          productId: 'water',
          lowStockThreshold: 2,
          unit: 'bottle',
        ),
      ],
    );

class _Reader implements InventoryHealthInputReader {
  _Reader(this.batch);

  final InventoryHealthInputBatch batch;
  int readCount = 0;

  @override
  Future<InventoryHealthInputBatch> read() async {
    readCount++;
    return batch;
  }
}

class _CompleterReader implements InventoryHealthInputReader {
  _CompleterReader(this.completer);

  final Completer<InventoryHealthInputBatch> completer;

  @override
  Future<InventoryHealthInputBatch> read() => completer.future;
}

class _RetryReader implements InventoryHealthInputReader {
  _RetryReader(this.batch);

  final InventoryHealthInputBatch batch;
  int readCount = 0;

  @override
  Future<InventoryHealthInputBatch> read() async {
    readCount++;
    if (readCount == 1) throw StateError('first read fails');
    return batch;
  }
}
