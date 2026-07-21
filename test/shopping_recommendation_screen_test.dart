import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/consumption/application/consumption_input_reader.dart';
import 'package:maqadi_v2/consumption/application/consumption_service.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_input_reader.dart';
import 'package:maqadi_v2/inventory_health/application/inventory_health_service.dart';
import 'package:maqadi_v2/inventory_health/domain/inventory_health_result.dart';
import 'package:maqadi_v2/low_stock/application/low_stock_service.dart';
import 'package:maqadi_v2/shopping_recommendation/application/shopping_recommendation_service.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_failure.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_input.dart';
import 'package:maqadi_v2/shopping_recommendation/domain/shopping_recommendation_result.dart';
import 'package:maqadi_v2/shopping_recommendation/engine/shopping_recommendation_engine.dart';
import 'package:maqadi_v2/shopping_recommendation/presentation/shopping_recommendation_screen.dart';

import 'shopping_recommendation_test_support.dart';

void main() {
  ShoppingRecommendationResult recommendation(
    ShoppingRecommendationInput input,
  ) =>
      (const ShoppingRecommendationEngine().evaluate(input)
              as ShoppingRecommendationItemSuccess)
          .result;

  Widget app(
    ShoppingRecommendationService service, {
    ValueChanged<String>? onOpen,
  }) =>
      MaterialApp(
        home: ShoppingRecommendationScreen(
          service: service,
          onOpenProduct: onOpen,
        ),
      );

  testWidgets('shows loading, all states, filtering, and product navigation',
      (tester) async {
    final pending = Completer<ShoppingRecommendationEvaluation>();
    final service = _QueuedRecommendationService([pending.future]);
    String? opened;
    await tester.pumpWidget(app(service, onOpen: (id) => opened = id));
    expect(
        find.byKey(const ValueKey('recommendation-loading')), findsOneWidget);

    pending.complete(ShoppingRecommendationEvaluationSuccess(results: [
      recommendation(inputForStatus(
        InventoryHealthStatus.outOfStock,
        id: 'buy-now',
      )),
      recommendation(recommendationInput(
        health: healthResult(id: 'buy-soon'),
        consumption: consumptionResult(id: 'buy-soon', totalConsumed: 9),
      )),
      recommendation(recommendationInput(
        health: healthResult(id: 'watch'),
        consumption: consumptionResult(
          id: 'watch',
          totalConsumed: 0,
          consumptionEvents: 0,
        ),
      )),
      recommendation(recommendationInput(
        health: healthResult(id: 'ignore'),
        consumption: consumptionResult(id: 'ignore'),
      )),
    ], failures: const {}));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommendation-state-buyNow')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('recommendation-state-buySoon')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('recommendation-state-watch')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recommendation-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ignore').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommendation-product-ignore')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('recommendation-product-buy-now')),
        findsNothing);

    await tester.tap(find.byKey(const ValueKey('recommendation-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buy now').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommendation-product-buy-now')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('recommendation-product-buy-soon')),
        findsNothing);
    expect(find.byKey(const ValueKey('recommendation-product-watch')),
        findsNothing);
    expect(find.byKey(const ValueKey('recommendation-product-ignore')),
        findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('recommendation-open-product-buy-now')),
    );
    expect(opened, 'buy-now');
  });

  testWidgets('shows empty state and refreshes into results', (tester) async {
    final result = recommendation(recommendationInput());
    final service = _QueuedRecommendationService([
      Future.value(ShoppingRecommendationEvaluationSuccess(
        results: const [],
        failures: const {},
      )),
      Future.value(ShoppingRecommendationEvaluationSuccess(
        results: [result],
        failures: const {},
      )),
    ]);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommendation-empty')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recommendation-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('Rice'), findsOneWidget);
    expect(service.calls, 2);
  });

  testWidgets('shows a batch error and retries successfully', (tester) async {
    final service = _QueuedRecommendationService([
      Future.value(const ShoppingRecommendationEvaluationFailure(
        ShoppingRecommendationFailure(
          code: ShoppingRecommendationFailureCode.upstreamHealthFailure,
          message: 'Health unavailable',
        ),
      )),
      Future.value(ShoppingRecommendationEvaluationSuccess(
        results: [recommendation(recommendationInput())],
        failures: const {},
      )),
    ]);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recommendation-error')), findsOneWidget);
    expect(find.text('Health unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Rice'), findsOneWidget);
  });

  testWidgets('shows explanations and item failures without mutation actions',
      (tester) async {
    final service = _QueuedRecommendationService([
      Future.value(ShoppingRecommendationEvaluationSuccess(
        results: [recommendation(recommendationInput())],
        failures: const {
          'beans': ShoppingRecommendationFailure(
            code: ShoppingRecommendationFailureCode.invalidNumericInput,
            message: 'Invalid evidence',
            productId: 'beans',
          ),
        },
      )),
    ]);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
    expect(find.text('Invalid evidence'), findsOneWidget);
    expect(find.text('Add to shopping list'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Delete'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('recommendation-explanation-rice')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recommendation explanation'), findsOneWidget);
    expect(find.text('healthyNoAction'), findsOneWidget);
    expect(find.text('normal'), findsOneWidget);
    expect(find.text('Consumption summary'), findsNWidgets(2));
  });
}

class _QueuedRecommendationService extends ShoppingRecommendationService {
  _QueuedRecommendationService(this.evaluations)
      : super(
          healthService: InventoryHealthService(
            inputReader: _UnusedHealthInputReader(),
          ),
          consumptionService: ConsumptionService(
            inputReader: _UnusedConsumptionInputReader(),
          ),
          lowStockService: LowStockService(
            healthService: InventoryHealthService(
              inputReader: _UnusedHealthInputReader(),
            ),
            consumptionService: ConsumptionService(
              inputReader: _UnusedConsumptionInputReader(),
            ),
          ),
        );

  final List<Future<ShoppingRecommendationEvaluation>> evaluations;
  int calls = 0;

  @override
  Future<ShoppingRecommendationEvaluation> evaluateInventory() {
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
