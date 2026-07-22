import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_line_builder/application/receipt_line_builder_service.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_line_builder/presentation/receipt_line_builder_debug_screen.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_understanding/application/receipt_understanding_service.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_understanding_failure.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_understanding_result.dart';
import 'package:maqadi_v2/receipt_understanding/engine/receipt_understanding_engine.dart';
import 'package:maqadi_v2/receipt_understanding/presentation/receipt_understanding_debug_screen.dart';

import 'receipt_understanding_test_support.dart';

void main() {
  final blocks = [
    ocrBlock('RECEIPT', y: 0, confidence: null),
    ocrBlock('BODY TEXT', x: 0, y: 45),
    ocrBlock('12.50', x: 80, y: 45, width: 20, confidence: 0.75),
    ocrBlock('TOTAL 12.50', y: 70),
    ocrBlock('THANK YOU', y: 95),
  ];
  final source = ocrResult(blocks);
  final classified = ReceiptUnderstandingResult(
    elements: const ReceiptUnderstandingEngine().classify(blocks),
    ocrOrderPreserved: true,
  );

  Widget app(ReceiptUnderstandingService service) => MaterialApp(
        home: ReceiptUnderstandingDebugScreen(
          service: service,
          ocrResult: source,
          ocrReadingOrderGuaranteed: true,
        ),
      );

  testWidgets('shows loading then classified elements with confidence',
      (tester) async {
    final pending = Completer<ReceiptUnderstandingResult>();
    await tester.pumpWidget(app(_QueuedService([pending.future])));
    expect(find.byKey(const ValueKey('receipt-understanding-loading')),
        findsOneWidget);
    pending.complete(classified);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-classified-elements')),
        findsOneWidget);
    expect(find.textContaining('OCR confidence: 0.75'), findsOneWidget);
  });

  testWidgets('shows original OCR blocks without changing their order',
      (tester) async {
    await tester.pumpWidget(app(_QueuedService([Future.value(classified)])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OCR blocks'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('receipt-original-blocks')), findsOneWidget);
    expect(find.text('RECEIPT'), findsOneWidget);
    expect(find.textContaining('Confidence: Not available'), findsOneWidget);
  });

  testWidgets('filters classified elements by type', (tester) async {
    await tester.pumpWidget(app(_QueuedService([Future.value(classified)])));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receipt-element-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Total').last);
    await tester.pumpAndSettle();
    expect(find.text('TOTAL 12.50'), findsOneWidget);
    expect(find.text('BODY TEXT'), findsNothing);
  });

  testWidgets('renders the bounding-box overlay', (tester) async {
    await tester.pumpWidget(app(_QueuedService([Future.value(classified)])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overlay'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-understanding-overlay')),
        findsOneWidget);
  });

  testWidgets('shows engine evidence without edit or business actions',
      (tester) async {
    await tester.pumpWidget(app(_QueuedService([Future.value(classified)])));
    await tester.pumpAndSettle();
    final total = classified.elements.firstWhere(
      (element) => element.type == ReceiptElementType.total,
    );
    await tester.tap(
      find.byKey(ValueKey('receipt-element-evidence-${total.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Classification evidence'), findsOneWidget);
    expect(find.text('total'), findsWidgets);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Match product'), findsNothing);
    expect(find.text('Create purchase'), findsNothing);
  });

  testWidgets('shows service errors and retries', (tester) async {
    final pending = Completer<ReceiptUnderstandingResult>();
    final service = _QueuedService([
      pending.future,
      Future.value(classified),
    ]);
    await tester.pumpWidget(app(service));
    pending.completeError(const ReceiptUnderstandingFailure(
      code: ReceiptUnderstandingFailureCode.classificationFailed,
      message: 'Structure unavailable',
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-understanding-error')),
        findsOneWidget);
    expect(find.text('Structure unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-classified-elements')),
        findsOneWidget);
  });

  testWidgets('shows an empty state', (tester) async {
    await tester.pumpWidget(app(_QueuedService([
      Future.value(ReceiptUnderstandingResult(
        elements: const [],
        ocrOrderPreserved: true,
      )),
    ])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-understanding-empty')),
        findsOneWidget);
  });

  testWidgets(
      'opens line debug with the existing result and invokes its service once',
      (tester) async {
    final understandingService = _QueuedService([Future.value(classified)]);
    final lineService = _CountingLineService();
    ReceiptUnderstandingResult? forwarded;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ReceiptUnderstandingDebugScreen(
          service: understandingService,
          ocrResult: source,
          ocrReadingOrderGuaranteed: true,
          onInspectLines: (result) {
            forwarded = result;
            Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ReceiptLineBuilderDebugScreen(
                  service: lineService,
                  elements: result.elements,
                ),
              ),
            );
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('عرض أسطر الإيصال'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('open-receipt-line-builder-debug')),
    );
    await tester.pumpAndSettle();

    expect(forwarded, same(classified));
    expect(understandingService.calls, 1);
    expect(lineService.calls, 1);
    expect(find.byKey(const ValueKey('receipt-line-builder-debug-screen')),
        findsOneWidget);
  });
}

class _QueuedService extends ReceiptUnderstandingService {
  _QueuedService(this.results);

  final List<Future<ReceiptUnderstandingResult>> results;
  int calls = 0;

  @override
  Future<ReceiptUnderstandingResult> understand(
    ReceiptOcrResult ocrResult, {
    bool ocrReadingOrderGuaranteed = false,
  }) {
    final index = calls++;
    return results[index];
  }
}

class _CountingLineService extends ReceiptLineBuilderService {
  int calls = 0;

  @override
  Future<ReceiptLineResult> build(List<ReceiptElement> elements) {
    calls++;
    return super.build(elements);
  }
}
