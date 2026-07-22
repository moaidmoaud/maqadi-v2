import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_benchmark/application/receipt_line_comparator.dart';
import 'package:maqadi_v2/receipt_benchmark/application/receipt_understanding_comparator.dart';
import 'package:maqadi_v2/receipt_benchmark/domain/receipt_benchmark_definition.dart';
import 'package:maqadi_v2/receipt_benchmark/domain/receipt_benchmark_ground_truth.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_understanding_result.dart';
import 'package:maqadi_v2/receipt_understanding/engine/receipt_understanding_engine.dart';

import 'receipt_benchmark_test_support.dart';
import 'receipt_line_builder_test_support.dart';

void main() {
  const understandingComparator = ReceiptUnderstandingComparator();
  const lineComparator = ReceiptLineComparator();

  test('parses manually declared ground truth independently from output', () {
    final definition = loadDan0001();
    expect(definition.receiptId, 'DAN-0001');
    expect(definition.syntheticFixture, isTrue);
    expect(definition.privateImageCommitted, isFalse);
    expect(definition.groundTruth.manuallyVerified, isTrue);
    expect(definition.groundTruth.scope, 'synthetic-redacted-fixture-only');
    expect(definition.groundTruth.expectedElements, hasLength(9));
    expect(definition.groundTruth.expectedLines, hasLength(2));
    expect(definition.groundTruth.expectedUnassignedKeys, hasLength(4));
  });

  test('understanding comparison reports the independent synthetic baseline',
      () {
    final definition = loadDan0001();
    final blocks =
        definition.fixtureBlocks.map((value) => value.toOcrBlock()).toList();
    final actual = ReceiptUnderstandingResult(
      elements: const ReceiptUnderstandingEngine().classify(blocks),
      ocrOrderPreserved: true,
    );
    final result = understandingComparator.compare(definition, actual).result;
    expect(
      result.correctlyClassifiedElements,
      8,
      reason: result.misclassifiedElements
          .map((mismatch) =>
              '${mismatch.fixtureKey}: ${mismatch.expectedType} -> ${mismatch.actualType}')
          .join(', '),
    );
    expect(result.classificationAccuracy, closeTo(8 / 9, 0.0000001));
    expect(result.misclassifiedElements.single.fixtureKey, 'price-b');
    expect(result.misclassifiedElements.single.expectedType,
        ReceiptElementType.price);
    expect(result.misclassifiedElements.single.actualType,
        ReceiptElementType.total);
    expect(result.ocrAccuracy, isNull);
  });

  test('detects misclassified elements and per-type differences', () {
    final definition = _simpleDefinition();
    final actual = ReceiptUnderstandingResult(
      elements: [
        receiptElement('actual', ReceiptElementType.quantity,
            text: 'ITEM', x: 0),
      ],
      ocrOrderPreserved: true,
    );
    final result = understandingComparator.compare(definition, actual).result;
    expect(result.misclassifiedElements.single.fixtureKey, 'item');
    expect(result.perType[ReceiptElementType.productName]!.correct, 0);
    expect(result.perType[ReceiptElementType.quantity]!.actual, 1);
    expect(result.classificationAccuracy, 0);
  });

  test('detects missing expected elements', () {
    final result = understandingComparator
        .compare(
          _simpleDefinition(),
          ReceiptUnderstandingResult(
              elements: const [], ocrOrderPreserved: true),
        )
        .result;
    expect(result.missingExpectedElements, ['item']);
  });

  test('detects unexpected actual elements', () {
    final definition = _simpleDefinition();
    final actual = ReceiptUnderstandingResult(
      elements: [
        receiptElement('extra', ReceiptElementType.price, text: 'EXTRA', x: 20),
      ],
      ocrOrderPreserved: true,
    );
    final result = understandingComparator.compare(definition, actual).result;
    expect(result.unexpectedElements, ['extra']);
  });

  test('understanding division by zero is explicit', () {
    final definition = ReceiptBenchmarkDefinition(
      receiptId: 'EMPTY',
      fixtureVersion: 'v1',
      syntheticFixture: true,
      privateImageCommitted: false,
      calibrationNotes: 'empty',
      fixtureBlocks: const [],
      groundTruth: ReceiptBenchmarkGroundTruth(
        manuallyVerified: true,
        scope: 'synthetic',
        ocrTextVerified: false,
        expectedElements: const [],
        expectedLines: const [],
        expectedUnassignedKeys: const [],
      ),
    );
    final result = understandingComparator
        .compare(
          definition,
          ReceiptUnderstandingResult(
              elements: const [], ocrOrderPreserved: true),
        )
        .result;
    expect(result.classificationAccuracy, 1);
  });

  test('line matching is independent of actual list order', () {
    final groundTruth = _lineGroundTruth();
    final actual = benchmarkLineResult([
      benchmarkLine(id: 'line-b', product: 'p2', price: 'v2'),
      benchmarkLine(id: 'line-a', product: 'p1', price: 'v1'),
    ]);
    final result = lineComparator.compare(
      groundTruth: groundTruth,
      actual: actual,
      actualIdToFixtureKey: const {
        'p1': 'p1',
        'v1': 'v1',
        'p2': 'p2',
        'v2': 'v2'
      },
      elementCorrectionKeys: const {},
    );
    expect(result.correctlyGroupedLines, 2);
    expect(result.precision, 1);
    expect(result.recall, 1);
    expect(result.f1, 1);
  });

  test('detects missing and unexpected lines', () {
    final result = lineComparator.compare(
      groundTruth: _lineGroundTruth(),
      actual: benchmarkLineResult([
        benchmarkLine(id: 'extra', product: 'p3', price: 'v3'),
      ]),
      actualIdToFixtureKey: const {'p3': 'p3', 'v3': 'v3'},
      elementCorrectionKeys: const {},
    );
    expect(result.missingExpectedLines, hasLength(2));
    expect(result.unexpectedLines, ['extra']);
    expect(result.manualCorrectionsEstimate, greaterThan(0));
  });

  test('detects wrong role attachment and completeness', () {
    final result = lineComparator.compare(
      groundTruth: _lineGroundTruth(),
      actual: benchmarkLineResult([
        benchmarkLine(
          id: 'line-a',
          product: 'p1',
          quantity: 'v1',
          completeness: ReceiptLineCompleteness.partial,
        ),
      ]),
      actualIdToFixtureKey: const {'p1': 'p1', 'v1': 'v1'},
      elementCorrectionKeys: const {},
    );
    expect(result.incorrectRoleAttachments.map((value) => value.role),
        containsAll(['quantity', 'price']));
    expect(result.completenessMismatches, ['line-a']);
  });

  test('compares expected and actual unassigned elements', () {
    final groundTruth = ReceiptBenchmarkGroundTruth(
      manuallyVerified: true,
      scope: 'synthetic',
      ocrTextVerified: false,
      expectedElements: const [],
      expectedLines: const [],
      expectedUnassignedKeys: const ['header'],
    );
    final result = lineComparator.compare(
      groundTruth: groundTruth,
      actual: benchmarkLineResult(
        const [],
        unassigned: [benchmarkUnassigned('footer')],
      ),
      actualIdToFixtureKey: const {'footer': 'footer'},
      elementCorrectionKeys: const {},
    );
    expect(result.missingExpectedUnassigned, {'header'});
    expect(result.unexpectedUnassigned, {'footer'});
  });

  test('line division by zero is explicit', () {
    final result = lineComparator.compare(
      groundTruth: ReceiptBenchmarkGroundTruth(
        manuallyVerified: true,
        scope: 'empty',
        ocrTextVerified: false,
        expectedElements: const [],
        expectedLines: const [],
        expectedUnassignedKeys: const [],
      ),
      actual: benchmarkLineResult(const []),
      actualIdToFixtureKey: const {},
      elementCorrectionKeys: const {},
    );
    expect(result.precision, 1);
    expect(result.recall, 1);
    expect(result.f1, 1);
  });

  test('manual corrections do not double count an element error', () {
    final result = lineComparator.compare(
      groundTruth: _lineGroundTruth(),
      actual: benchmarkLineResult(const []),
      actualIdToFixtureKey: const {},
      elementCorrectionKeys: const {'p1'},
    );
    expect(result.manualCorrectionsEstimate, lessThan(3));
  });
}

ReceiptBenchmarkDefinition _simpleDefinition() => ReceiptBenchmarkDefinition(
      receiptId: 'SIMPLE',
      fixtureVersion: 'v1',
      syntheticFixture: true,
      privateImageCommitted: false,
      calibrationNotes: 'test',
      fixtureBlocks: const [
        ReceiptBenchmarkFixtureBlock(
          fixtureKey: 'item',
          text: 'ITEM',
          confidence: 1,
          region: ReceiptOcrRegion(x: 0, y: 0, width: 40, height: 10),
        ),
      ],
      groundTruth: ReceiptBenchmarkGroundTruth(
        manuallyVerified: true,
        scope: 'synthetic',
        ocrTextVerified: false,
        expectedElements: const [
          ExpectedReceiptElement(
            fixtureKey: 'item',
            type: ReceiptElementType.productName,
          ),
        ],
        expectedLines: const [],
        expectedUnassignedKeys: const [],
      ),
    );

ReceiptBenchmarkGroundTruth _lineGroundTruth() => ReceiptBenchmarkGroundTruth(
      manuallyVerified: true,
      scope: 'synthetic',
      ocrTextVerified: false,
      expectedElements: const [],
      expectedLines: const [
        ExpectedReceiptLine(
          fixtureKey: 'line-a',
          productKey: 'p1',
          priceKey: 'v1',
          quantityKey: null,
          discountKey: null,
          taxKey: null,
          lineTotalKey: null,
          completeness: ReceiptLineCompleteness.complete,
        ),
        ExpectedReceiptLine(
          fixtureKey: 'line-b',
          productKey: 'p2',
          priceKey: 'v2',
          quantityKey: null,
          discountKey: null,
          taxKey: null,
          lineTotalKey: null,
          completeness: ReceiptLineCompleteness.complete,
        ),
      ],
      expectedUnassignedKeys: const [],
    );
