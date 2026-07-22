import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_line_builder/application/receipt_line_builder_service.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_evidence.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_failure.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  test('validates input and invokes the engine exactly once', () async {
    final input = productRow();
    final original = List<ReceiptElement>.from(input);
    final engine = _CountingEngine();
    final result = await ReceiptLineBuilderService(engine: engine).build(input);
    expect(engine.calls, 1);
    expect(result.lines.single.completeness, ReceiptLineCompleteness.complete);
    expect(input, orderedEquals(original));
  });

  test('rejects duplicate element IDs before invoking the engine', () async {
    final engine = _CountingEngine();
    await expectLater(
      ReceiptLineBuilderService(engine: engine).build([
        receiptElement('same', ReceiptElementType.productName),
        receiptElement('same', ReceiptElementType.price, x: 45),
      ]),
      throwsA(isA<ReceiptLineFailure>().having(
        (failure) => failure.code,
        'code',
        ReceiptLineFailureCode.duplicateElementId,
      )),
    );
    expect(engine.calls, 0);
  });

  test('maps unexpected engine exceptions to groupingFailed', () async {
    await expectLater(
      ReceiptLineBuilderService(engine: _ThrowingEngine()).build(productRow()),
      throwsA(isA<ReceiptLineFailure>().having(
        (failure) => failure.code,
        'code',
        ReceiptLineFailureCode.groupingFailed,
      )),
    );
  });

  test('rejects an unknown output reference', () async {
    await expectLater(
      ReceiptLineBuilderService(
        engine: _ResultEngine(_resultWith(_line(productId: 'missing'))),
      ).build([receiptElement('product', ReceiptElementType.productName)]),
      throwsA(isA<ReceiptLineFailure>().having(
        (failure) => failure.code,
        'code',
        ReceiptLineFailureCode.invalidReference,
      )),
    );
  });

  test('rejects duplicate role assignments across lines', () async {
    final line = _line(productId: 'product');
    await expectLater(
      ReceiptLineBuilderService(
        engine: _ResultEngine(ReceiptLineResult(
          lines: [line, line],
          unassignedElements: const [],
          failures: const [],
        )),
      ).build([receiptElement('product', ReceiptElementType.productName)]),
      throwsA(isA<ReceiptLineFailure>().having(
        (failure) => failure.code,
        'code',
        ReceiptLineFailureCode.duplicateRoleAssignment,
      )),
    );
  });

  test('rejects a role referencing an incompatible element type', () async {
    await expectLater(
      ReceiptLineBuilderService(
        engine: _ResultEngine(_resultWith(_line(productId: 'price'))),
      ).build([receiptElement('price', ReceiptElementType.price)]),
      throwsA(isA<ReceiptLineFailure>().having(
        (failure) => failure.code,
        'code',
        ReceiptLineFailureCode.invalidReference,
      )),
    );
  });

  test('rejects inconsistent completeness and anchor evidence', () async {
    await expectLater(
      ReceiptLineBuilderService(
        engine: _ResultEngine(_resultWith(_line(
          productId: 'product',
          completeness: ReceiptLineCompleteness.complete,
        ))),
      ).build([receiptElement('product', ReceiptElementType.productName)]),
      throwsA(isA<ReceiptLineFailure>()),
    );
  });

  test('returns immutable result collections', () async {
    final result = await const ReceiptLineBuilderService().build(productRow());
    expect(() => result.lines.add(result.lines.single), throwsUnsupportedError);
    expect(() => result.unassignedElements.clear(), throwsUnsupportedError);
    expect(() => result.failures.clear(), throwsUnsupportedError);
  });
}

class _CountingEngine extends ReceiptLineBuilderEngine {
  int calls = 0;

  @override
  ReceiptLineResult build(List<ReceiptElement> elements) {
    calls++;
    return super.build(elements);
  }
}

class _ThrowingEngine extends ReceiptLineBuilderEngine {
  @override
  ReceiptLineResult build(List<ReceiptElement> elements) =>
      throw StateError('grouping failed');
}

class _ResultEngine extends ReceiptLineBuilderEngine {
  _ResultEngine(this.result);

  final ReceiptLineResult result;

  @override
  ReceiptLineResult build(List<ReceiptElement> elements) => result;
}

ReceiptLineResult _resultWith(ReceiptLine line) => ReceiptLineResult(
      lines: [line],
      unassignedElements: const [],
      failures: const [],
    );

ReceiptLine _line({
  required String productId,
  ReceiptLineCompleteness completeness = ReceiptLineCompleteness.partial,
}) =>
    ReceiptLine(
      id: 'line',
      productElementId: productId,
      priceElementId: null,
      quantityElementId: null,
      discountElementId: null,
      taxElementId: null,
      lineTotalElementId: null,
      completeness: completeness,
      evidence: ReceiptLineEvidence(
        anchorElementId: productId,
        attachedElementIds: [productId],
        normalizedVerticalDistances: const {},
        normalizedHorizontalDistances: const {},
        overlapMetrics: const {},
        columnEvidence: const {},
        appliedGroupingRule: 'test',
        rejectedCandidates: const {},
        confidenceFactors: const [],
        summary: 'test',
      ),
    );
