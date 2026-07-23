import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/application/receipt_extraction_benchmark_service.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_input.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_result.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/presentation/receipt_extraction_benchmark_screen.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_extraction_benchmark_test_support.dart';
import 'receipt_line_builder_test_support.dart';

void main() {
  testWidgets('shows loading then overall metrics and missing line reasons',
      (tester) async {
    const realService = ReceiptExtractionBenchmarkService();
    final input = extractionInput(
      elements: [
        receiptElement(
          'store',
          ReceiptElementType.storeName,
          text: 'Tamimi',
        ),
        receiptElement(
          'product',
          ReceiptElementType.productName,
          text: 'Garlic Bag',
        ),
        receiptElement('price', ReceiptElementType.price, text: '10'),
      ],
      lines: [
        extractionLine(id: 'line-product', productId: 'product'),
        extractionLine(
          id: 'line-orphan',
          priceId: 'price',
          completeness: ReceiptLineCompleteness.orphan,
        ),
      ],
    );
    final pending = Completer<ReceiptExtractionBenchmarkResult>();
    await tester.pumpWidget(_app(_QueuedService([pending.future]), input));
    expect(
      find.byKey(const ValueKey('receipt-extraction-benchmark-loading')),
      findsOneWidget,
    );

    pending.complete(await realService.analyze(input));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('receipt-extraction-benchmark-report')),
      findsOneWidget,
    );
    expect(find.text('Store: Tamimi'), findsOneWidget);
    expect(find.text('Coverage: 50.0%'), findsOneWidget);
    expect(find.text('Lines containing Product Text: 1'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('receipt-extraction-benchmark-report')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.text('Orphan line: 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('receipt-extraction-missing-line-orphan')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Orphan Recovery Summary'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Orphan Recovery Summary'), findsOneWidget);
    expect(find.text('Unrecoverable: 1'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recovery comparison'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Recovery comparison'), findsOneWidget);
    expect(find.text('Before Recovery: 50.0%'), findsOneWidget);
    expect(find.text('After Recovery: 50.0%'), findsOneWidget);
    expect(find.text('Recovered Orphans: 0'), findsOneWidget);
    expect(find.text('Remaining Orphans: 1'), findsOneWidget);
  });

  testWidgets('shows full coverage with an explicit empty missing-line state',
      (tester) async {
    final input = extractionInput(
      elements: fullCoverageElements(),
      lines: [
        extractionLine(id: 'line-1', productId: 'garlic'),
        extractionLine(id: 'line-2', productId: 'potatoes'),
      ],
    );
    await tester.pumpWidget(_app(
      const ReceiptExtractionBenchmarkService(),
      input,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Coverage: 100.0%'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('receipt-extraction-benchmark-report')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('receipt-extraction-no-missing-lines')),
      findsOneWidget,
    );
    expect(find.text('Save'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('shows an error and retries read-only analysis', (tester) async {
    final input = extractionInput();
    final result =
        await const ReceiptExtractionBenchmarkService().analyze(input);
    final pending = Completer<ReceiptExtractionBenchmarkResult>();
    final service = _QueuedService([
      pending.future,
      Future.value(result),
    ]);
    await tester.pumpWidget(_app(service, input));
    pending.completeError(StateError('diagnostic failure'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('receipt-extraction-benchmark-error')),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('receipt-extraction-benchmark-report')),
      findsOneWidget,
    );
    expect(service.calls, 2);
  });
}

Widget _app(
  ReceiptExtractionBenchmarkService service,
  ReceiptExtractionBenchmarkInput input,
) =>
    MaterialApp(
      home: ReceiptExtractionBenchmarkScreen(service: service, input: input),
    );

class _QueuedService extends ReceiptExtractionBenchmarkService {
  _QueuedService(this.results);

  final List<Future<ReceiptExtractionBenchmarkResult>> results;
  int calls = 0;

  @override
  Future<ReceiptExtractionBenchmarkResult> analyze(
    ReceiptExtractionBenchmarkInput input,
  ) =>
      results[calls++];
}
