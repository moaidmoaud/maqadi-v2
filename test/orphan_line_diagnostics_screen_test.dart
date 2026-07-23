import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/orphan_line_diagnostics/application/orphan_line_diagnostics_service.dart';
import 'package:maqadi_v2/orphan_line_diagnostics/presentation/orphan_line_diagnostics_screen.dart';
import 'package:maqadi_v2/receipt_line_builder/application/receipt_line_builder_service.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_line_builder/presentation/receipt_line_builder_debug_screen.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  final competingElements = [
    receiptElement(
      'product',
      ReceiptElementType.productName,
      x: 0,
      width: 40,
    ),
    receiptElement(
      'near',
      ReceiptElementType.price,
      x: 45,
      width: 10,
    ),
    receiptElement(
      'far',
      ReceiptElementType.price,
      x: 60,
      width: 10,
    ),
  ];
  final competingResult =
      const ReceiptLineBuilderEngine().build(competingElements);

  testWidgets('renders orphan list and selectable diagnostic evidence',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OrphanLineDiagnosticsScreen(
        service: const OrphanLineDiagnosticsService(),
        elements: competingElements,
        lineResult: competingResult,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('orphan-line-diagnostics-list')),
      findsOneWidget,
    );
    expect(
        find.textContaining('Multiple competing candidates'), findsOneWidget);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('Receipt Elements'), findsOneWidget);
    expect(find.text('Grouping attempt'), findsOneWidget);
    expect(find.text('Product element exists: Yes'), findsOneWidget);
    expect(find.text('Price element exists: Yes'), findsOneWidget);
    expect(find.text('Quantity element exists: No'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Failure reason'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('Failure reason'), findsOneWidget);
    expect(find.text('Recovery hint'), findsOneWidget);
    expect(find.text('Recoverable: Yes'), findsOneWidget);
  });

  testWidgets('shows an empty diagnostics state', (tester) async {
    final elements = productRow();
    final result = const ReceiptLineBuilderEngine().build(elements);
    await tester.pumpWidget(MaterialApp(
      home: OrphanLineDiagnosticsScreen(
        service: const OrphanLineDiagnosticsService(),
        elements: elements,
        lineResult: result,
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('orphan-line-diagnostics-empty')),
      findsOneWidget,
    );
  });

  testWidgets('navigates from line debug using the existing line result',
      (tester) async {
    final lineService = _QueuedLineService([Future.value(competingResult)]);
    ReceiptLineResult? forwarded;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ReceiptLineBuilderDebugScreen(
          service: lineService,
          elements: competingElements,
          onInspectOrphanDiagnostics: (result) {
            forwarded = result;
            Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => OrphanLineDiagnosticsScreen(
                service: const OrphanLineDiagnosticsService(),
                elements: competingElements,
                lineResult: result,
              ),
            ));
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('open-orphan-line-diagnostics')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('open-orphan-line-diagnostics')),
    );
    await tester.pumpAndSettle();

    expect(forwarded, same(competingResult));
    expect(lineService.calls, 1);
    expect(
      find.byKey(const ValueKey('orphan-line-diagnostics-screen')),
      findsOneWidget,
    );
  });
}

class _QueuedLineService extends ReceiptLineBuilderService {
  _QueuedLineService(this.results);

  final List<Future<ReceiptLineResult>> results;
  int calls = 0;

  @override
  Future<ReceiptLineResult> build(List<ReceiptElement> elements) =>
      results[calls++];
}
