import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/consumption/application/consumption_input_reader.dart';
import 'package:maqadi_v2/consumption/application/consumption_service.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_input_reader.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_service.dart';
import 'package:maqadi_v2/low_stock/application/low_stock_service.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_failure.dart';
import 'package:maqadi_v2/low_stock/domain/low_stock_result.dart';
import 'package:maqadi_v2/low_stock/engine/low_stock_engine.dart';
import 'package:maqadi_v2/low_stock/presentation/low_stock_screen.dart';

import 'low_stock_test_support.dart';

void main() {
  LowStockResult prediction(String id, double consumed, {int events = 2}) {
    final evaluation = const LowStockEngine().evaluate(lowStockInput(
      health: healthResult(id: id, name: 'Product $id'),
      consumption: consumptionResult(
        id: id,
        name: 'Product $id',
        totalConsumed: consumed,
        consumptionEvents: events,
      ),
    ));
    return (evaluation as LowStockItemSuccess).result;
  }

  Widget app(LowStockService service, {ValueChanged<String>? onOpen}) =>
      MaterialApp(
        home: LowStockScreen(service: service, onOpenProduct: onOpen),
      );

  testWidgets('shows loading, results, filtering, and product navigation',
      (tester) async {
    final pending = Completer<LowStockEvaluation>();
    final service = _QueuedLowStockService([pending.future]);
    String? opened;
    await tester.pumpWidget(app(service, onOpen: (id) => opened = id));
    expect(find.byKey(const ValueKey('low-stock-loading')), findsOneWidget);

    pending.complete(LowStockEvaluationSuccess(results: [
      prediction('normal', 7),
      prediction('monitor', 0, events: 0),
      prediction('soon', 9),
    ], failures: const {}));
    await tester.pumpAndSettle();
    expect(find.text('Product normal'), findsOneWidget);
    expect(find.text('Product monitor'), findsOneWidget);
    expect(find.text('Product soon'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('low-stock-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Low soon').last);
    await tester.pumpAndSettle();
    expect(find.text('Product normal'), findsNothing);
    expect(find.text('Product monitor'), findsNothing);
    expect(find.text('Product soon'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('low-stock-open-product-soon')));
    expect(opened, 'soon');
  });

  testWidgets('shows empty state and refreshes into results', (tester) async {
    final service = _QueuedLowStockService([
      Future.value(LowStockEvaluationSuccess(
        results: const [],
        failures: const {},
      )),
      Future.value(LowStockEvaluationSuccess(
        results: [prediction('rice', 7)],
        failures: const {},
      )),
    ]);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('low-stock-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('low-stock-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('Product rice'), findsOneWidget);
    expect(service.calls, 2);
  });

  testWidgets('shows a batch error and retries successfully', (tester) async {
    final service = _QueuedLowStockService([
      Future.value(const LowStockEvaluationFailure(
        LowStockFailure(
          code: LowStockFailureCode.upstreamHealthFailure,
          message: 'Health unavailable',
        ),
      )),
      Future.value(LowStockEvaluationSuccess(
        results: [prediction('rice', 7)],
        failures: const {},
      )),
    ]);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('low-stock-error')), findsOneWidget);
    expect(find.text('Health unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Product rice'), findsOneWidget);
  });

  testWidgets('shows explanations and item failures without edit actions',
      (tester) async {
    final service = _QueuedLowStockService([
      Future.value(LowStockEvaluationSuccess(
        results: [prediction('rice', 8)],
        failures: const {
          'beans': LowStockFailure(
            code: LowStockFailureCode.invalidNumericInput,
            message: 'Invalid evidence',
            productId: 'beans',
          ),
        },
      )),
    ]);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.text('Invalid evidence'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('low-stock-explanation-rice')));
    await tester.pumpAndSettle();
    expect(find.text('Prediction explanation'), findsOneWidget);
    expect(find.text('projectedAtThreshold'), findsOneWidget);
    expect(find.text('14 days'), findsOneWidget);
  });
}

class _QueuedLowStockService extends LowStockService {
  _QueuedLowStockService(this.evaluations)
      : super(
          healthService: InventoryHealthService(
            inputReader: _UnusedHealthInputReader(),
          ),
          consumptionService: ConsumptionService(
            inputReader: _UnusedConsumptionInputReader(),
          ),
        );

  final List<Future<LowStockEvaluation>> evaluations;
  int calls = 0;

  @override
  Future<LowStockEvaluation> evaluateInventory() {
    final index = calls++;
    return evaluations[index];
  }
}

class _UnusedHealthInputReader implements InventoryHealthInputReader {
  @override
  Future<InventoryHealthInputBatch> read() => throw UnimplementedError();
}

class _UnusedConsumptionInputReader implements ConsumptionInputReader {
  @override
  Future<ConsumptionInputBatch> read() => throw UnimplementedError();
}
