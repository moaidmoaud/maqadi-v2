import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_benchmark/application/receipt_benchmark_runner.dart';
import 'package:maqadi_v2/receipt_benchmark/domain/receipt_benchmark_definition.dart';
import 'package:maqadi_v2/receipt_benchmark/domain/receipt_benchmark_failure.dart';
import 'package:maqadi_v2/receipt_benchmark/domain/receipt_benchmark_result.dart';
import 'package:maqadi_v2/receipt_benchmark/presentation/receipt_benchmark_report_screen.dart';
import 'package:maqadi_v2/receipt_line_builder/application/receipt_line_builder_service.dart';
import 'package:maqadi_v2/receipt_line_builder/presentation/receipt_line_builder_debug_screen.dart';

import 'receipt_benchmark_test_support.dart';

void main() {
  late ReceiptBenchmarkDefinition definition;
  late ReceiptBenchmarkResult baseline;

  setUpAll(() async {
    definition = loadDan0001();
    baseline = await ReceiptBenchmarkRunner().run(definition);
  });

  Widget app(ReceiptBenchmarkRunner runner) => MaterialApp(
        home: ReceiptBenchmarkReportScreen(
          runner: runner,
          definition: definition,
        ),
      );

  testWidgets('shows loading then the deterministic benchmark report',
      (tester) async {
    final pending = Completer<ReceiptBenchmarkResult>();
    await tester.pumpWidget(app(_QueuedRunner([pending.future])));
    expect(find.byKey(const ValueKey('receipt-benchmark-loading')),
        findsOneWidget);
    pending.complete(baseline);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('receipt-benchmark-report')), findsOneWidget);
    expect(find.textContaining('OCR accuracy: Unavailable'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('receipt-benchmark-report')),
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Understanding accuracy: 88.9%'), findsOneWidget);
    expect(find.textContaining('Expected elements: 9'), findsOneWidget);
    expect(find.textContaining('Actual elements: 9'), findsOneWidget);
  });

  testWidgets('switches between expected, actual, and mismatch overlays',
      (tester) async {
    await tester.pumpWidget(app(_QueuedRunner([Future.value(baseline)])));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('receipt-benchmark-report')),
      const Offset(0, -650),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-benchmark-overlay-mismatches')),
        findsOneWidget);
    await tester.tap(find.text('Expected'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-benchmark-overlay-expected')),
        findsOneWidget);
    await tester.tap(find.text('Actual'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receipt-benchmark-overlay-actual')),
        findsOneWidget);
  });

  testWidgets('shows failures and retries without mutation actions',
      (tester) async {
    final pending = Completer<ReceiptBenchmarkResult>();
    final runner = _QueuedRunner([pending.future, Future.value(baseline)]);
    await tester.pumpWidget(app(runner));
    pending.completeError(const ReceiptBenchmarkFailure(
      code: ReceiptBenchmarkFailureCode.comparisonFailed,
      message: 'Benchmark unavailable',
    ));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('receipt-benchmark-error')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('receipt-benchmark-report')), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('line debug renders every engine-provided role and metric',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReceiptLineBuilderDebugScreen(
        service: const ReceiptLineBuilderService(),
        elements: baseline.actualUnderstanding.elements,
      ),
    ));
    await tester.pumpAndSettle();
    final line = baseline.actualLines.lines.first;
    await tester.tap(find.byKey(ValueKey('receipt-line-evidence-${line.id}')));
    await tester.pumpAndSettle();
    for (final label in [
      'Completeness',
      'Product',
      'Price',
      'Quantity',
      'Discount',
      'Tax',
      'Line total',
      'Vertical',
      'Horizontal',
      'Overlap',
      'Row / column',
      'Rule',
      'Factors',
      'Rejected',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });
}

class _QueuedRunner extends ReceiptBenchmarkRunner {
  _QueuedRunner(this.results);

  final List<Future<ReceiptBenchmarkResult>> results;
  int calls = 0;

  @override
  Future<ReceiptBenchmarkResult> run(
    ReceiptBenchmarkDefinition definition, {
    String resultVersion = 'baseline',
  }) =>
      results[calls++];
}
