import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/application/receipt_extraction_benchmark_service.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_input.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_result.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/presentation/receipt_extraction_benchmark_screen.dart';
import 'package:maqadi_v2/receipt_line_builder/application/receipt_line_builder_service.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_line_builder/presentation/receipt_line_builder_debug_screen.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_reliability_gate/application/receipt_reliability_report_service.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_understanding_result.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  final elements = productRow();
  final lineResult = const ReceiptLineBuilderEngine().build(elements);

  testWidgets('benchmark debug action appears only after lines are available',
      (tester) async {
    final pending = Completer<ReceiptLineResult>();
    await tester.pumpWidget(MaterialApp(
      home: ReceiptLineBuilderDebugScreen(
        service: _QueuedLineService([pending.future]),
        elements: elements,
        onInspectExtractionBenchmark: (_) {},
      ),
    ));

    expect(
      find.byKey(const ValueKey('open-receipt-extraction-benchmark')),
      findsNothing,
    );

    pending.complete(lineResult);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('open-receipt-extraction-benchmark')),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Receipt Extraction Benchmark'),
      findsOneWidget,
    );
  });

  testWidgets(
      'opens existing benchmark with current results and preserves candidate action',
      (tester) async {
    final lineService = _QueuedLineService([Future.value(lineResult)]);
    final benchmarkService = _CountingBenchmarkService();
    final understandingResult = ReceiptUnderstandingResult(
      elements: elements,
      ocrOrderPreserved: true,
    );
    final ocrResult = ReceiptOcrResult(
      text: elements.map((element) => element.text).join('\n'),
      blocks: [
        for (final element in elements)
          ReceiptOcrBlock(text: element.text, lines: const []),
      ],
    );
    ReceiptLineResult? forwarded;
    var candidateCalls = 0;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ReceiptLineBuilderDebugScreen(
          service: lineService,
          elements: elements,
          onInspectCandidates: (_) => candidateCalls++,
          onInspectExtractionBenchmark: (result) {
            forwarded = result;
            Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => ReceiptExtractionBenchmarkScreen(
                service: benchmarkService,
                input: ReceiptExtractionBenchmarkInput(
                  receiptId: 'runtime-test',
                  ocrResult: ocrResult,
                  understandingResult: understandingResult,
                  lineResult: result,
                ),
              ),
            ));
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('open-candidate-generation-debug')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('open-receipt-extraction-benchmark')),
    );
    await tester.pumpAndSettle();

    expect(forwarded, same(lineResult));
    expect(lineService.calls, 1);
    expect(benchmarkService.calls, 1);
    expect(candidateCalls, 0);
    expect(
      find.byKey(const ValueKey('receipt-extraction-benchmark-screen')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('receipt-extraction-benchmark-report')),
      findsOneWidget,
    );
    expect(find.text('Receipt: runtime-test'), findsOneWidget);
  });

  testWidgets('opens the existing reliability comparison from the benchmark',
      (tester) async {
    final understandingResult = ReceiptUnderstandingResult(
      elements: elements,
      ocrOrderPreserved: true,
    );
    final ocrResult = ReceiptOcrResult(
      text: elements.map((element) => element.text).join('\n'),
      blocks: [
        for (final element in elements)
          ReceiptOcrBlock(text: element.text, lines: const []),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: ReceiptExtractionBenchmarkScreen(
        service: const ReceiptExtractionBenchmarkService(),
        reliabilityReportService: const ReceiptReliabilityReportService(),
        input: ReceiptExtractionBenchmarkInput(
          receiptId: 'runtime-reliability-test',
          ocrResult: ocrResult,
          understandingResult: understandingResult,
          lineResult: lineResult,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('open-receipt-reliability-gate-report')),
      findsOneWidget,
    );
    expect(find.byTooltip('Receipt Reliability Gate'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('open-receipt-reliability-gate-report')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('receipt-reliability-gate-report-screen')),
      findsOneWidget,
    );
    expect(find.text('PASS'), findsOneWidget);
    expect(find.textContaining('Product Text Coverage'), findsOneWidget);
    expect(find.textContaining('Recovered Orphans'), findsOneWidget);
    expect(find.textContaining('Remaining Orphans'), findsOneWidget);
    expect(find.textContaining('UNCHANGED — PASS'), findsOneWidget);
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

class _CountingBenchmarkService extends ReceiptExtractionBenchmarkService {
  int calls = 0;

  @override
  Future<ReceiptExtractionBenchmarkResult> analyze(
    ReceiptExtractionBenchmarkInput input,
  ) {
    calls++;
    return super.analyze(input);
  }
}
