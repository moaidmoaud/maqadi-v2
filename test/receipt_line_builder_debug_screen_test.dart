import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_line_builder/application/receipt_line_builder_service.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_failure.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_line_builder/presentation/receipt_line_builder_debug_screen.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  final elements = [
    ...productRow(quantity: true),
    receiptElement('header', ReceiptElementType.header, y: -20),
    receiptElement('no-box', ReceiptElementType.price, withoutGeometry: true),
  ];
  final result = const ReceiptLineBuilderEngine().build(elements);

  Widget app(ReceiptLineBuilderService service,
          {List<ReceiptElement>? input}) =>
      MaterialApp(
        home: ReceiptLineBuilderDebugScreen(
          service: service,
          elements: input ?? elements,
        ),
      );

  testWidgets('shows loading then receipt lines', (tester) async {
    final pending = Completer<ReceiptLineResult>();
    await tester.pumpWidget(app(_QueuedService([pending.future])));
    expect(find.byKey(const ValueKey('receipt-line-builder-loading')),
        findsOneWidget);
    pending.complete(result);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-lines')), findsOneWidget);
    expect(find.text('Complete line'), findsOneWidget);
  });

  testWidgets('filters lines by completeness', (tester) async {
    final mixed = const ReceiptLineBuilderEngine().build([
      ...productRow(),
      receiptElement('orphan', ReceiptElementType.price, y: 40),
    ]);
    await tester.pumpWidget(app(_QueuedService([Future.value(mixed)])));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('receipt-line-completeness-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orphan').last);
    await tester.pumpAndSettle();
    expect(find.text('Orphan line'), findsOneWidget);
    expect(find.text('Complete line'), findsNothing);
  });

  testWidgets('selects a line and highlights referenced elements',
      (tester) async {
    await tester.pumpWidget(app(_QueuedService([Future.value(result)])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete line'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elements'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-line-element-highlights')),
        findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsNWidgets(3));
  });

  testWidgets('renders grouping overlay', (tester) async {
    await tester.pumpWidget(app(_QueuedService([Future.value(result)])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overlay'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-line-grouping-overlay')),
        findsOneWidget);
  });

  testWidgets('shows unassigned and geometry-unavailable evidence',
      (tester) async {
    await tester.pumpWidget(app(_QueuedService([Future.value(result)])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unassigned'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-line-unassigned-elements')),
        findsOneWidget);
    expect(find.text('geometryUnavailable'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('unassigned-evidence-no-box')));
    await tester.pumpAndSettle();
    expect(find.text('Grouping evidence'), findsOneWidget);
    expect(find.textContaining('not spatially grouped'), findsOneWidget);
  });

  testWidgets('displays engine-produced policy, summary, and split trace',
      (tester) async {
    final traced = const ReceiptLineBuilderEngine().build([
      receiptElement('product', ReceiptElementType.productName, x: 0),
      receiptElement('price', ReceiptElementType.price, x: 150),
    ]);
    await tester.pumpWidget(app(_QueuedService([Future.value(traced)])));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spatial trace'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('receipt-line-spatial-trace')),
        findsOneWidget);
    expect(find.text('Calibration policy'), findsOneWidget);
    expect(find.text('rowVerticalDistanceTolerance: 0.75'), findsOneWidget);
    expect(find.text('rowMinimumOverlapRatio: 0.30'), findsOneWidget);
    expect(find.text('columnGapTolerance: 8.00'), findsOneWidget);
    expect(find.text('Median positive height: 10.00'), findsOneWidget);
    expect(find.text('Complete: 0'), findsOneWidget);
    expect(find.text('Partial: 1'), findsOneWidget);
    expect(find.text('Orphan: 1'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Row decisions'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Row decisions'), findsOneWidget);
    expect(find.text('Column decisions'), findsOneWidget);
    expect(find.textContaining('JOIN, vertical=0.000'), findsOneWidget);
    expect(find.textContaining('SPLIT, gap=11.000'), findsOneWidget);
  });

  testWidgets('renders accepted and rejected candidate decision traces',
      (tester) async {
    final traced = const ReceiptLineBuilderEngine().build([
      receiptElement('product', ReceiptElementType.productName, width: 40),
      receiptElement('near', ReceiptElementType.price, x: 45),
      receiptElement('far', ReceiptElementType.price, x: 70),
    ]);
    await tester.pumpWidget(app(_QueuedService([Future.value(traced)])));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spatial trace'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Decision Trace'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('receipt-line-decision-trace')),
        findsOneWidget);
    expect(find.textContaining('Anchor product'), findsOneWidget);
    expect(find.textContaining('near (price) · ACCEPTED · accepted'),
        findsOneWidget);
    expect(
      find.textContaining('far (price) · REJECTED · fartherFromProductAnchor'),
      findsOneWidget,
    );
    expect(find.textContaining('horizontalGap=0.500'), findsOneWidget);
    expect(find.textContaining('verticalOverlap=1.000'), findsWidgets);
  });

  testWidgets('shows service errors and retries', (tester) async {
    final pending = Completer<ReceiptLineResult>();
    final service = _QueuedService([pending.future, Future.value(result)]);
    await tester.pumpWidget(app(service));
    pending.completeError(const ReceiptLineFailure(
      code: ReceiptLineFailureCode.groupingFailed,
      message: 'Grouping unavailable',
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-line-builder-error')),
        findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-lines')), findsOneWidget);
  });

  testWidgets('shows an empty state without editing actions', (tester) async {
    final empty = ReceiptLineResult(
      lines: const [],
      unassignedElements: const [],
      failures: const [],
    );
    await tester.pumpWidget(
        app(_QueuedService([Future.value(empty)]), input: const []));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-line-builder-empty')),
        findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });
}

class _QueuedService extends ReceiptLineBuilderService {
  _QueuedService(this.results);

  final List<Future<ReceiptLineResult>> results;
  int calls = 0;

  @override
  Future<ReceiptLineResult> build(List<ReceiptElement> elements) =>
      results[calls++];
}
