import '../../receipt_understanding/domain/receipt_element.dart';
import '../../receipt_understanding/domain/receipt_element_type.dart';
import '../../receipt_understanding/domain/receipt_understanding_result.dart';
import '../domain/receipt_benchmark_definition.dart';
import '../domain/receipt_benchmark_result.dart';

class ReceiptUnderstandingComparison {
  ReceiptUnderstandingComparison({
    required this.result,
    required Map<String, String> actualIdToFixtureKey,
  }) : actualIdToFixtureKey = Map.unmodifiable(actualIdToFixtureKey);

  final ReceiptUnderstandingBenchmarkResult result;
  final Map<String, String> actualIdToFixtureKey;
}

class ReceiptUnderstandingComparator {
  const ReceiptUnderstandingComparator();

  ReceiptUnderstandingComparison compare(
    ReceiptBenchmarkDefinition definition,
    ReceiptUnderstandingResult actual,
  ) {
    final signatureKeys = <String, List<String>>{};
    for (final block in definition.fixtureBlocks) {
      signatureKeys
          .putIfAbsent(block.signature, () => [])
          .add(block.fixtureKey);
    }
    final signatureOffsets = <String, int>{};
    final actualIdToKey = <String, String>{};
    final actualByKey = <String, ReceiptElement>{};
    final unexpected = <String>[];
    for (final element in actual.elements) {
      final signature = ReceiptBenchmarkFixtureBlock.signatureFor(
        element.text,
        element.boundingBox,
      );
      final keys = signatureKeys[signature];
      final offset = signatureOffsets[signature] ?? 0;
      if (keys == null || offset >= keys.length) {
        unexpected.add(element.id);
        continue;
      }
      final key = keys[offset];
      signatureOffsets[signature] = offset + 1;
      actualIdToKey[element.id] = key;
      actualByKey[key] = element;
    }

    final expectedByKey = {
      for (final expected in definition.groundTruth.expectedElements)
        expected.fixtureKey: expected,
    };
    final misclassified = <ReceiptElementMismatch>[];
    final missing = <String>[];
    var correct = 0;
    for (final entry in expectedByKey.entries) {
      final element = actualByKey[entry.key];
      if (element == null) {
        missing.add(entry.key);
      } else if (element.type == entry.value.type) {
        correct++;
      } else {
        misclassified.add(ReceiptElementMismatch(
          fixtureKey: entry.key,
          expectedType: entry.value.type,
          actualType: element.type,
        ));
      }
    }
    for (final key in actualByKey.keys) {
      if (!expectedByKey.containsKey(key)) unexpected.add(key);
    }

    final perType = <ReceiptElementType, ReceiptBenchmarkTypeMetrics>{};
    for (final type in ReceiptElementType.values) {
      final expectedCount = expectedByKey.values
          .where((expected) => expected.type == type)
          .length;
      final actualCount =
          actual.elements.where((element) => element.type == type).length;
      final correctCount = expectedByKey.entries.where((entry) {
        final element = actualByKey[entry.key];
        return entry.value.type == type && element?.type == type;
      }).length;
      perType[type] = ReceiptBenchmarkTypeMetrics(
        expected: expectedCount,
        actual: actualCount,
        correct: correctCount,
      );
    }
    final expectedCount = expectedByKey.length;
    final accuracy = expectedCount == 0
        ? actual.elements.isEmpty
            ? 1.0
            : 0.0
        : correct / expectedCount;
    return ReceiptUnderstandingComparison(
      actualIdToFixtureKey: actualIdToKey,
      result: ReceiptUnderstandingBenchmarkResult(
        expectedElementCount: expectedCount,
        actualElementCount: actual.elements.length,
        correctlyClassifiedElements: correct,
        misclassifiedElements: misclassified,
        missingExpectedElements: missing,
        unexpectedElements: unexpected,
        perType: perType,
        classificationAccuracy: accuracy,
        unknownCount: actual.elements
            .where((element) => element.type == ReceiptElementType.unknown)
            .length,
        ocrAccuracy: null,
      ),
    );
  }
}
