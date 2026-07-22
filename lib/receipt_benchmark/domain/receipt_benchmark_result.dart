import '../../receipt_line_builder/domain/receipt_calibration_policy.dart';
import '../../receipt_line_builder/domain/receipt_line.dart';
import '../../receipt_line_builder/domain/receipt_line_completeness.dart';
import '../../receipt_line_builder/domain/receipt_line_result.dart';
import '../../receipt_understanding/domain/receipt_element.dart';
import '../../receipt_understanding/domain/receipt_element_type.dart';
import '../../receipt_understanding/domain/receipt_understanding_result.dart';
import 'receipt_benchmark_definition.dart';
import 'receipt_benchmark_metrics.dart';

class ReceiptElementMismatch {
  const ReceiptElementMismatch({
    required this.fixtureKey,
    required this.expectedType,
    required this.actualType,
  });

  final String fixtureKey;
  final ReceiptElementType expectedType;
  final ReceiptElementType actualType;
}

class ReceiptBenchmarkTypeMetrics {
  const ReceiptBenchmarkTypeMetrics({
    required this.expected,
    required this.actual,
    required this.correct,
  });

  final int expected;
  final int actual;
  final int correct;
}

class ReceiptUnderstandingBenchmarkResult {
  ReceiptUnderstandingBenchmarkResult({
    required this.expectedElementCount,
    required this.actualElementCount,
    required this.correctlyClassifiedElements,
    required Iterable<ReceiptElementMismatch> misclassifiedElements,
    required Iterable<String> missingExpectedElements,
    required Iterable<String> unexpectedElements,
    required Map<ReceiptElementType, ReceiptBenchmarkTypeMetrics> perType,
    required this.classificationAccuracy,
    required this.unknownCount,
    required this.ocrAccuracy,
  })  : misclassifiedElements = List.unmodifiable(misclassifiedElements),
        missingExpectedElements = List.unmodifiable(missingExpectedElements),
        unexpectedElements = List.unmodifiable(unexpectedElements),
        perType = Map.unmodifiable(perType);

  final int expectedElementCount;
  final int actualElementCount;
  final int correctlyClassifiedElements;
  final List<ReceiptElementMismatch> misclassifiedElements;
  final List<String> missingExpectedElements;
  final List<String> unexpectedElements;
  final Map<ReceiptElementType, ReceiptBenchmarkTypeMetrics> perType;
  final double classificationAccuracy;
  final int unknownCount;
  final double? ocrAccuracy;
}

class ReceiptRoleMismatch {
  const ReceiptRoleMismatch({
    required this.expectedLineKey,
    required this.role,
    required this.expectedElementKey,
    required this.actualElementKey,
  });

  final String expectedLineKey;
  final String role;
  final String? expectedElementKey;
  final String? actualElementKey;
}

class ReceiptLineBenchmarkResult {
  ReceiptLineBenchmarkResult({
    required this.expectedLineCount,
    required this.actualLineCount,
    required this.correctlyGroupedLines,
    required Iterable<String> missingExpectedLines,
    required Iterable<String> unexpectedLines,
    required Iterable<ReceiptRoleMismatch> incorrectRoleAttachments,
    required Iterable<String> completenessMismatches,
    required Map<ReceiptLineCompleteness, int> expectedCompletenessCounts,
    required Map<ReceiptLineCompleteness, int> actualCompletenessCounts,
    required this.actualUnassignedCount,
    required Iterable<String> missingExpectedUnassigned,
    required Iterable<String> unexpectedUnassigned,
    required this.precision,
    required this.recall,
    required this.f1,
    required this.manualCorrectionsEstimate,
  })  : missingExpectedLines = List.unmodifiable(missingExpectedLines),
        unexpectedLines = List.unmodifiable(unexpectedLines),
        incorrectRoleAttachments = List.unmodifiable(incorrectRoleAttachments),
        completenessMismatches = List.unmodifiable(completenessMismatches),
        expectedCompletenessCounts =
            Map.unmodifiable(expectedCompletenessCounts),
        actualCompletenessCounts = Map.unmodifiable(actualCompletenessCounts),
        missingExpectedUnassigned =
            List.unmodifiable(missingExpectedUnassigned),
        unexpectedUnassigned = List.unmodifiable(unexpectedUnassigned);

  final int expectedLineCount;
  final int actualLineCount;
  final int correctlyGroupedLines;
  final List<String> missingExpectedLines;
  final List<String> unexpectedLines;
  final List<ReceiptRoleMismatch> incorrectRoleAttachments;
  final List<String> completenessMismatches;
  final Map<ReceiptLineCompleteness, int> expectedCompletenessCounts;
  final Map<ReceiptLineCompleteness, int> actualCompletenessCounts;
  final int actualUnassignedCount;
  final List<String> missingExpectedUnassigned;
  final List<String> unexpectedUnassigned;
  final double precision;
  final double recall;
  final double f1;
  final int manualCorrectionsEstimate;
}

class ReceiptBenchmarkResult {
  ReceiptBenchmarkResult({
    required this.definition,
    required this.resultVersion,
    required this.policy,
    required this.understanding,
    required this.lines,
    required this.metrics,
    required this.actualUnderstanding,
    required this.actualLines,
    required Map<String, String> actualElementIdToFixtureKey,
  }) : actualElementIdToFixtureKey =
            Map.unmodifiable(actualElementIdToFixtureKey);

  final ReceiptBenchmarkDefinition definition;
  final String resultVersion;
  final ReceiptCalibrationPolicy policy;
  final ReceiptUnderstandingBenchmarkResult understanding;
  final ReceiptLineBenchmarkResult lines;
  final ReceiptBenchmarkMetrics metrics;
  final ReceiptUnderstandingResult actualUnderstanding;
  final ReceiptLineResult actualLines;
  final Map<String, String> actualElementIdToFixtureKey;

  String? fixtureKeyForElement(ReceiptElement element) =>
      actualElementIdToFixtureKey[element.id];

  Map<String, String?> actualRoles(ReceiptLine line) => Map.unmodifiable({
        'product': _key(line.productElementId),
        'quantity': _key(line.quantityElementId),
        'price': _key(line.priceElementId),
        'lineTotal': _key(line.lineTotalElementId),
        'discount': _key(line.discountElementId),
        'tax': _key(line.taxElementId),
      });

  String? _key(String? elementId) =>
      elementId == null ? null : actualElementIdToFixtureKey[elementId];
}
