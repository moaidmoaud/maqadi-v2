import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_benchmark/application/receipt_benchmark_runner.dart';
import 'package:maqadi_v2/receipt_benchmark/domain/receipt_benchmark_definition.dart';
import 'package:maqadi_v2/receipt_benchmark/domain/receipt_benchmark_failure.dart';
import 'package:maqadi_v2/receipt_benchmark/domain/receipt_benchmark_ground_truth.dart';
import 'package:maqadi_v2/receipt_line_builder/application/receipt_line_builder_service.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_understanding/application/receipt_understanding_service.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_understanding_result.dart';

import 'receipt_benchmark_test_support.dart';

void main() {
  test('DAN-0001 synthetic benchmark produces its declared baseline', () async {
    final result = await ReceiptBenchmarkRunner().run(loadDan0001());
    expect(result.definition.receiptId, 'DAN-0001');
    expect(result.metrics.understandingAccuracy, closeTo(8 / 9, 0.0000001));
    expect(result.metrics.lineGroupingPrecision, closeTo(1 / 3, 0.0000001));
    expect(result.metrics.lineGroupingRecall, 0.5);
    expect(result.metrics.lineGroupingF1, 0.4);
    expect(result.metrics.correctLineCount, 1);
    expect(result.metrics.expectedLineCount, 2);
    expect(result.metrics.actualLineCount, 3);
    expect(result.metrics.unassignedCount, 3);
    expect(result.metrics.manualCorrectionsEstimate, 2);
    expect(result.understanding.misclassifiedElements.single.fixtureKey,
        'price-b');
    expect(result.lines.missingExpectedUnassigned, {'receipt-total'});
  });

  test('runner evaluates Understanding and Line Builder exactly once',
      () async {
    final understanding = _CountingUnderstandingService();
    final lines = _CountingLineService();
    await ReceiptBenchmarkRunner(
      understandingService: understanding,
      lineBuilderService: lines,
    ).run(loadDan0001());
    expect(understanding.calls, 1);
    expect(lines.calls, 1);
  });

  test('benchmark results are deterministic for the same fixture and version',
      () async {
    final runner = ReceiptBenchmarkRunner();
    final definition = loadDan0001();
    final first = await runner.run(definition, resultVersion: 'rc-1');
    final second = await runner.run(definition, resultVersion: 'rc-1');
    expect(first.resultVersion, second.resultVersion);
    expect(first.metrics.understandingAccuracy,
        second.metrics.understandingAccuracy);
    expect(first.metrics.lineGroupingF1, second.metrics.lineGroupingF1);
    expect(first.actualLines.lines.map((line) => line.id),
        orderedEquals(second.actualLines.lines.map((line) => line.id)));
  });

  test('invalid manual-ground-truth status fails before evaluation', () async {
    final definition = loadDan0001();
    final invalid = ReceiptBenchmarkDefinition(
      receiptId: definition.receiptId,
      fixtureVersion: definition.fixtureVersion,
      syntheticFixture: true,
      privateImageCommitted: false,
      calibrationNotes: definition.calibrationNotes,
      fixtureBlocks: definition.fixtureBlocks,
      groundTruth: ReceiptBenchmarkGroundTruth(
        manuallyVerified: false,
        scope: 'not-verified',
        ocrTextVerified: false,
        expectedElements: definition.groundTruth.expectedElements,
        expectedLines: definition.groundTruth.expectedLines,
        expectedUnassignedKeys: definition.groundTruth.expectedUnassignedKeys,
      ),
    );
    await expectLater(
      ReceiptBenchmarkRunner().run(invalid),
      throwsA(isA<ReceiptBenchmarkFailure>().having(
        (failure) => failure.code,
        'code',
        ReceiptBenchmarkFailureCode.invalidDefinition,
      )),
    );
  });

  test('maps Understanding failures without invoking Line Builder', () async {
    final lines = _CountingLineService();
    await expectLater(
      ReceiptBenchmarkRunner(
        understandingService: _FailingUnderstandingService(),
        lineBuilderService: lines,
      ).run(loadDan0001()),
      throwsA(isA<ReceiptBenchmarkFailure>().having(
        (failure) => failure.code,
        'code',
        ReceiptBenchmarkFailureCode.understandingFailed,
      )),
    );
    expect(lines.calls, 0);
  });

  test('maps Line Builder failures', () async {
    await expectLater(
      ReceiptBenchmarkRunner(
        lineBuilderService: _FailingLineService(),
      ).run(loadDan0001()),
      throwsA(isA<ReceiptBenchmarkFailure>().having(
        (failure) => failure.code,
        'code',
        ReceiptBenchmarkFailureCode.lineBuilderFailed,
      )),
    );
  });

  test('large synthetic benchmark remains reproducible', () async {
    final source = loadDan0001();
    final blocks = <ReceiptBenchmarkFixtureBlock>[];
    final expected = <ExpectedReceiptElement>[];
    for (var index = 0; index < 1000; index++) {
      final block = source.fixtureBlocks[index % source.fixtureBlocks.length];
      blocks.add(ReceiptBenchmarkFixtureBlock(
        fixtureKey: '${block.fixtureKey}-$index',
        text: '${block.text} $index',
        confidence: block.confidence,
        region: ReceiptOcrRegion(
          x: block.region!.x,
          y: index * 10.0,
          width: block.region!.width,
          height: block.region!.height,
        ),
      ));
      expected.add(ExpectedReceiptElement(
        fixtureKey: '${block.fixtureKey}-$index',
        type: ReceiptElementType.unknown,
      ));
    }
    final definition = ReceiptBenchmarkDefinition(
      receiptId: 'LARGE',
      fixtureVersion: 'v1',
      syntheticFixture: true,
      privateImageCommitted: false,
      calibrationNotes: 'performance fixture',
      fixtureBlocks: blocks,
      groundTruth: ReceiptBenchmarkGroundTruth(
        manuallyVerified: true,
        scope: 'synthetic-performance',
        ocrTextVerified: false,
        expectedElements: expected,
        expectedLines: const [],
        expectedUnassignedKeys: expected.map((value) => value.fixtureKey),
      ),
    );
    final result = await ReceiptBenchmarkRunner().run(definition);
    expect(result.understanding.actualElementCount, 1000);
  });
}

class _CountingUnderstandingService extends ReceiptUnderstandingService {
  int calls = 0;

  @override
  Future<ReceiptUnderstandingResult> understand(
    ReceiptOcrResult ocrResult, {
    bool ocrReadingOrderGuaranteed = false,
  }) {
    calls++;
    return super.understand(
      ocrResult,
      ocrReadingOrderGuaranteed: ocrReadingOrderGuaranteed,
    );
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

class _FailingUnderstandingService extends ReceiptUnderstandingService {
  @override
  Future<ReceiptUnderstandingResult> understand(
    ReceiptOcrResult ocrResult, {
    bool ocrReadingOrderGuaranteed = false,
  }) =>
      throw StateError('understanding unavailable');
}

class _FailingLineService extends ReceiptLineBuilderService {
  @override
  Future<ReceiptLineResult> build(List<ReceiptElement> elements) =>
      throw StateError('line builder unavailable');
}
