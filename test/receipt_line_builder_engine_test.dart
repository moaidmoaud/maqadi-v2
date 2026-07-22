import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_failure.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/unassigned_receipt_element.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  const engine = ReceiptLineBuilderEngine();

  test('returns an immutable empty result', () {
    final result = engine.build(const []);
    expect(result.lines, isEmpty);
    expect(result.unassignedElements, isEmpty);
    expect(result.failures, isEmpty);
    expect(() => result.lines.addAll(const []), throwsUnsupportedError);
  });

  test('groups product and price into a complete line', () {
    final result = engine.build(productRow());
    final line = result.lines.single;
    expect(line.completeness, ReceiptLineCompleteness.complete);
    expect(line.productElementId, 'a-product');
    expect(line.priceElementId, 'a-price');
  });

  test('product without price is partial', () {
    final line = engine.build(productRow(price: false)).lines.single;
    expect(line.completeness, ReceiptLineCompleteness.partial);
    expect(line.productElementId, isNotNull);
    expect(line.priceElementId, isNull);
  });

  test('product and quantity without price is partial', () {
    final line =
        engine.build(productRow(quantity: true, price: false)).lines.single;
    expect(line.completeness, ReceiptLineCompleteness.partial);
    expect(line.quantityElementId, 'a-quantity');
  });

  test('product with attached roles but no price remains partial', () {
    final line = engine
        .build(productRow(price: false, discount: true, tax: true))
        .lines
        .single;
    expect(line.completeness, ReceiptLineCompleteness.partial);
    expect(line.discountElementId, 'a-discount');
    expect(line.taxElementId, 'a-tax');
  });

  for (final entry in const {
    ReceiptElementType.price: 'priceElementId',
    ReceiptElementType.quantity: 'quantityElementId',
    ReceiptElementType.discount: 'discountElementId',
    ReceiptElementType.tax: 'taxElementId',
    ReceiptElementType.total: 'lineTotalElementId',
  }.entries) {
    test('${entry.key.name} without product becomes an orphan', () {
      final line =
          engine.build([receiptElement('orphan', entry.key)]).lines.single;
      expect(line.completeness, ReceiptLineCompleteness.orphan);
      expect(line.productElementId, isNull);
      expect(line.referencedElementIds, ['orphan']);
    });
  }

  test('missing product roles remain separate orphan lines', () {
    final result = engine.build([
      receiptElement('quantity', ReceiptElementType.quantity, x: 0),
      receiptElement('price', ReceiptElementType.price, x: 20),
    ]);
    expect(result.lines, hasLength(2));
    expect(
        result.lines.every(
            (line) => line.completeness == ReceiptLineCompleteness.orphan),
        isTrue);
  });

  test('missing geometry is unassigned with geometryUnavailable evidence', () {
    final result = engine.build([
      receiptElement(
        'no-box',
        ReceiptElementType.productName,
        withoutGeometry: true,
      ),
    ]);
    expect(result.lines, isEmpty);
    final value = result.unassignedElements.single;
    expect(
        value.reasonCode, UnassignedReceiptElementReason.geometryUnavailable);
    expect(value.evidence.appliedGroupingRule, 'geometryUnavailable');
  });

  test('invalid geometry produces a failure and remains unassigned', () {
    final result = engine.build([
      receiptElement(
        'bad-box',
        ReceiptElementType.price,
        width: -1,
      ),
    ]);
    expect(result.lines, isEmpty);
    expect(result.failures.single.code, ReceiptLineFailureCode.invalidGeometry);
    expect(result.unassignedElements.single.elementId, 'bad-box');
  });

  test('excluded element types are returned unassigned', () {
    final result = engine.build([
      for (final type in const [
        ReceiptElementType.header,
        ReceiptElementType.footer,
        ReceiptElementType.metadata,
        ReceiptElementType.storeName,
        ReceiptElementType.unknown,
      ])
        receiptElement(type.name, type),
    ]);
    expect(result.lines, isEmpty);
    expect(result.unassignedElements, hasLength(5));
    expect(
      result.unassignedElements.every((value) =>
          value.reasonCode ==
          UnassignedReceiptElementReason.excludedElementType),
      isTrue,
    );
  });

  test('nearest of multiple prices is attached and the other is orphaned', () {
    final result = engine.build([
      receiptElement('product', ReceiptElementType.productName, width: 40),
      receiptElement('near', ReceiptElementType.price, x: 45),
      receiptElement('far', ReceiptElementType.price, x: 70),
    ]);
    final complete = result.lines.singleWhere(
        (line) => line.completeness == ReceiptLineCompleteness.complete);
    final orphan = result.lines.singleWhere(
        (line) => line.completeness == ReceiptLineCompleteness.orphan);
    expect(complete.priceElementId, 'near');
    expect(orphan.priceElementId, 'far');
    expect(complete.evidence.rejectedCandidates, contains('far'));
  });

  test('nearest of multiple quantities is attached and the other is orphaned',
      () {
    final result = engine.build([
      receiptElement('product', ReceiptElementType.productName, width: 40),
      receiptElement('near', ReceiptElementType.quantity, x: 45),
      receiptElement('far', ReceiptElementType.quantity, x: 70),
    ]);
    final partial = result.lines.singleWhere(
        (line) => line.completeness == ReceiptLineCompleteness.partial);
    expect(partial.quantityElementId, 'near');
    expect(result.lines.where((line) => line.quantityElementId == 'far'),
        hasLength(1));
  });

  test('multiple products receive their nearest spatial prices', () {
    final result = engine.build([
      receiptElement('p1', ReceiptElementType.productName, x: 0, width: 25),
      receiptElement('v1', ReceiptElementType.price, x: 30, width: 10),
      receiptElement('p2', ReceiptElementType.productName, x: 80, width: 25),
      receiptElement('v2', ReceiptElementType.price, x: 110, width: 10),
    ]);
    expect(result.lines, hasLength(2));
    expect(
      result.lines
          .singleWhere((line) => line.productElementId == 'p1')
          .priceElementId,
      'v1',
    );
    expect(
      result.lines
          .singleWhere((line) => line.productElementId == 'p2')
          .priceElementId,
      'v2',
    );
  });

  test('receipt total on its own row never populates a product line total', () {
    final result = engine.build([
      ...productRow(y: 0),
      receiptElement('receipt-total', ReceiptElementType.total, y: 30),
    ]);
    final product =
        result.lines.singleWhere((line) => line.productElementId != null);
    final total =
        result.lines.singleWhere((line) => line.lineTotalElementId != null);
    expect(product.lineTotalElementId, isNull);
    expect(total.completeness, ReceiptLineCompleteness.orphan);
  });

  test('same-row line total attaches after price', () {
    final line = engine.build(productRow(lineTotal: true)).lines.single;
    expect(line.lineTotalElementId, 'a-total');
    expect(line.priceElementId, 'a-price');
  });

  test('rows are established before columns and block cross-row attachment',
      () {
    final result = engine.build([
      receiptElement('product', ReceiptElementType.productName, y: 0),
      receiptElement('price', ReceiptElementType.price, x: 45, y: 20),
    ]);
    expect(result.lines, hasLength(2));
    expect(
        result.lines.map((line) => line.completeness),
        containsAll(
            [ReceiptLineCompleteness.partial, ReceiptLineCompleteness.orphan]));
  });

  test('column separation blocks a distant same-row attachment', () {
    final result = engine.build([
      receiptElement('product', ReceiptElementType.productName, x: 0),
      receiptElement('price', ReceiptElementType.price, x: 150),
    ]);
    expect(result.lines, hasLength(2));
    expect(result.lines.first.completeness, ReceiptLineCompleteness.partial);
    expect(result.lines.last.completeness, ReceiptLineCompleteness.orphan);
  });

  test('median-height normalization is scale independent', () {
    final small = engine.build(productRow(scale: 1)).lines.single;
    final large = engine.build(productRow(prefix: 'b', scale: 5)).lines.single;
    expect(small.completeness, large.completeness);
    expect(
        small.evidence.normalizedHorizontalDistances.values.single,
        closeTo(
            large.evidence.normalizedHorizontalDistances.values.single, 0.001));
  });

  test('identical input produces stable IDs and ordering', () {
    final input = [...productRow(), ...productRow(prefix: 'b', y: 30)];
    final first = engine.build(input);
    final second = engine.build(input);
    expect(first.lines.map((line) => line.id),
        orderedEquals(second.lines.map((line) => line.id)));
  });

  test('evidence contains all approved spatial explanations', () {
    final evidence =
        engine.build(productRow(quantity: true)).lines.single.evidence;
    expect(evidence.anchorElementId, 'a-product');
    expect(evidence.attachedElementIds,
        containsAll(['a-product', 'a-quantity', 'a-price']));
    expect(evidence.normalizedVerticalDistances, isNotEmpty);
    expect(evidence.normalizedHorizontalDistances, isNotEmpty);
    expect(evidence.overlapMetrics, isNotEmpty);
    expect(evidence.columnEvidence, isNotEmpty);
    expect(evidence.appliedGroupingRule, isNotEmpty);
    expect(evidence.confidenceFactors, contains('median-height-normalized'));
    expect(evidence.summary, isNotEmpty);
  });

  test('text cannot create grouping without spatial geometry', () {
    final result = engine.build([
      receiptElement('product', ReceiptElementType.productName,
          text: 'SAME', withoutGeometry: true),
      receiptElement('price', ReceiptElementType.price,
          text: 'SAME', withoutGeometry: true),
    ]);
    expect(result.lines, isEmpty);
    expect(result.unassignedElements, hasLength(2));
  });

  test('mixed Arabic and English text does not alter spatial grouping', () {
    final line = engine
        .build([
          receiptElement('product', ReceiptElementType.productName,
              text: 'منتج Product', width: 40),
          receiptElement('price', ReceiptElementType.price,
              text: '12.00 ريال', x: 45),
        ])
        .lines
        .single;
    expect(line.completeness, ReceiptLineCompleteness.complete);
  });

  test('left-to-right geometry groups without textual interpretation', () {
    final line = engine
        .build([
          receiptElement('ltr-product', ReceiptElementType.productName, x: 0),
          receiptElement('ltr-price', ReceiptElementType.price, x: 45),
        ])
        .lines
        .single;
    expect(line.productElementId, 'ltr-product');
    expect(line.priceElementId, 'ltr-price');
  });

  test('mirrored right-to-left geometry groups deterministically', () {
    final input = [
      receiptElement('rtl-price', ReceiptElementType.price, x: 0),
      receiptElement('rtl-product', ReceiptElementType.productName, x: 45),
    ];
    final first = engine.build(input).lines.single;
    final second = engine.build(input).lines.single;
    expect(first.productElementId, 'rtl-product');
    expect(first.priceElementId, 'rtl-price');
    expect(first.id, second.id);
  });

  test('large receipts group deterministically without dropping elements', () {
    final input = <ReceiptElement>[];
    for (var index = 0; index < 2000; index++) {
      input.addAll(productRow(prefix: '$index', y: index * 20.0));
    }
    final result = engine.build(input);
    expect(result.lines, hasLength(2000));
    expect(
        result.lines.every(
            (line) => line.completeness == ReceiptLineCompleteness.complete),
        isTrue);
  });
}
