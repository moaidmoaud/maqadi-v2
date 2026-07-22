import '../../receipt_line_builder/application/receipt_line_builder_service.dart';
import '../../receipt_line_builder/domain/receipt_calibration_policy.dart';
import '../../receipt_line_builder/domain/receipt_line_result.dart';
import '../../receipt_line_builder/engine/receipt_line_builder_engine.dart';
import '../../receipt_understanding/application/receipt_understanding_service.dart';
import '../../receipt_understanding/domain/receipt_understanding_result.dart';
import '../domain/receipt_benchmark_definition.dart';
import '../domain/receipt_benchmark_failure.dart';
import '../domain/receipt_benchmark_metrics.dart';
import '../domain/receipt_benchmark_result.dart';
import 'receipt_line_comparator.dart';
import 'receipt_understanding_comparator.dart';

class ReceiptBenchmarkRunner {
  ReceiptBenchmarkRunner({
    ReceiptUnderstandingService understandingService =
        const ReceiptUnderstandingService(),
    ReceiptLineBuilderService? lineBuilderService,
    ReceiptCalibrationPolicy policy = const ReceiptCalibrationPolicy(),
    ReceiptUnderstandingComparator understandingComparator =
        const ReceiptUnderstandingComparator(),
    ReceiptLineComparator lineComparator = const ReceiptLineComparator(),
  })  : _understandingService = understandingService,
        _lineBuilderService = lineBuilderService ??
            ReceiptLineBuilderService(
              engine: ReceiptLineBuilderEngine(policy: policy),
            ),
        _policy = policy,
        _understandingComparator = understandingComparator,
        _lineComparator = lineComparator;

  final ReceiptUnderstandingService _understandingService;
  final ReceiptLineBuilderService _lineBuilderService;
  final ReceiptCalibrationPolicy _policy;
  final ReceiptUnderstandingComparator _understandingComparator;
  final ReceiptLineComparator _lineComparator;

  Future<ReceiptBenchmarkResult> run(
    ReceiptBenchmarkDefinition definition, {
    String resultVersion = 'baseline',
  }) async {
    _validate(definition);
    late final ReceiptUnderstandingResult actualUnderstanding;
    try {
      actualUnderstanding = await _understandingService.understand(
        definition.toOcrResult(),
        ocrReadingOrderGuaranteed: true,
      );
    } catch (error) {
      throw ReceiptBenchmarkFailure(
        code: ReceiptBenchmarkFailureCode.understandingFailed,
        message: 'Receipt Understanding benchmark evaluation failed.',
        cause: error,
      );
    }

    final understanding =
        _understandingComparator.compare(definition, actualUnderstanding);
    late final ReceiptLineResult actualLines;
    try {
      actualLines =
          await _lineBuilderService.build(actualUnderstanding.elements);
    } catch (error) {
      throw ReceiptBenchmarkFailure(
        code: ReceiptBenchmarkFailureCode.lineBuilderFailed,
        message: 'Receipt Line Builder benchmark evaluation failed.',
        cause: error,
      );
    }

    final elementCorrectionKeys = <String>{
      ...understanding.result.misclassifiedElements
          .map((value) => value.fixtureKey),
      ...understanding.result.missingExpectedElements,
      ...understanding.result.unexpectedElements,
    };
    late final ReceiptLineBenchmarkResult lineResult;
    try {
      lineResult = _lineComparator.compare(
        groundTruth: definition.groundTruth,
        actual: actualLines,
        actualIdToFixtureKey: understanding.actualIdToFixtureKey,
        elementCorrectionKeys: elementCorrectionKeys,
      );
    } catch (error) {
      throw ReceiptBenchmarkFailure(
        code: ReceiptBenchmarkFailureCode.comparisonFailed,
        message: 'Receipt benchmark comparison failed.',
        cause: error,
      );
    }
    final metrics = ReceiptBenchmarkMetrics(
      understandingAccuracy: understanding.result.classificationAccuracy,
      lineGroupingPrecision: lineResult.precision,
      lineGroupingRecall: lineResult.recall,
      lineGroupingF1: lineResult.f1,
      correctLineCount: lineResult.correctlyGroupedLines,
      expectedLineCount: lineResult.expectedLineCount,
      actualLineCount: lineResult.actualLineCount,
      unassignedCount: lineResult.actualUnassignedCount,
      misclassifiedElementCount:
          understanding.result.misclassifiedElements.length,
      manualCorrectionsEstimate: lineResult.manualCorrectionsEstimate,
    );
    return ReceiptBenchmarkResult(
      definition: definition,
      resultVersion: resultVersion,
      policy: _policy,
      understanding: understanding.result,
      lines: lineResult,
      metrics: metrics,
      actualUnderstanding: actualUnderstanding,
      actualLines: actualLines,
      actualElementIdToFixtureKey: understanding.actualIdToFixtureKey,
    );
  }

  void _validate(ReceiptBenchmarkDefinition definition) {
    if (definition.receiptId.trim().isEmpty ||
        definition.fixtureVersion.trim().isEmpty ||
        !_policy.isValid ||
        !definition.groundTruth.manuallyVerified) {
      throw const ReceiptBenchmarkFailure(
        code: ReceiptBenchmarkFailureCode.invalidDefinition,
        message: 'Benchmark definition or calibration policy is invalid.',
      );
    }
    final fixtureKeys = <String>{};
    for (final block in definition.fixtureBlocks) {
      if (block.fixtureKey.isEmpty || !fixtureKeys.add(block.fixtureKey)) {
        throw const ReceiptBenchmarkFailure(
          code: ReceiptBenchmarkFailureCode.invalidDefinition,
          message: 'Benchmark fixture keys must be unique and non-empty.',
        );
      }
    }
    final expectedElementKeys = <String>{};
    for (final expected in definition.groundTruth.expectedElements) {
      if (!fixtureKeys.contains(expected.fixtureKey) ||
          !expectedElementKeys.add(expected.fixtureKey)) {
        throw const ReceiptBenchmarkFailure(
          code: ReceiptBenchmarkFailureCode.invalidDefinition,
          message: 'Expected elements must reference unique fixture keys.',
        );
      }
    }
    final expectedLineKeys = <String>{};
    for (final line in definition.groundTruth.expectedLines) {
      if (line.fixtureKey.isEmpty || !expectedLineKeys.add(line.fixtureKey)) {
        throw const ReceiptBenchmarkFailure(
          code: ReceiptBenchmarkFailureCode.invalidDefinition,
          message: 'Expected line keys must be unique and non-empty.',
        );
      }
      for (final key in line.referencedKeys) {
        if (!expectedElementKeys.contains(key)) {
          throw const ReceiptBenchmarkFailure(
            code: ReceiptBenchmarkFailureCode.invalidDefinition,
            message: 'Expected lines must reference expected elements.',
          );
        }
      }
    }
    for (final key in definition.groundTruth.expectedUnassignedKeys) {
      if (!expectedElementKeys.contains(key)) {
        throw const ReceiptBenchmarkFailure(
          code: ReceiptBenchmarkFailureCode.invalidDefinition,
          message: 'Expected unassigned keys must reference expected elements.',
        );
      }
    }
  }
}
