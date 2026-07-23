import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/application/receipt_extraction_benchmark_service.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_result.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_extraction_benchmark_test_support.dart';
import 'receipt_line_builder_test_support.dart';

void main() {
  const service = ReceiptExtractionBenchmarkService();

  test('calculates full product text coverage', () async {
    final result = await service.analyze(extractionInput(
      elements: fullCoverageElements(),
      lines: [
        extractionLine(id: 'line-1', productId: 'garlic'),
        extractionLine(id: 'line-2', productId: 'potatoes'),
      ],
      ocrTexts: const ['Tamimi', 'Garlic Bag', 'Potatoes Bag'],
    ));

    expect(result.storeName, 'Tamimi');
    expect(result.metrics.ocrTextBlocks, 3);
    expect(result.metrics.receiptElements, 3);
    expect(result.metrics.receiptLines, 2);
    expect(result.metrics.linesContainingProductText, 2);
    expect(result.metrics.linesWithoutProductText, 0);
    expect(result.metrics.recoverableProductLines, 2);
    expect(result.metrics.productTextCoverage, 1);
    expect(result.metrics.recoverableProductLinesPercentage, 1);
    expect(result.missingLines, isEmpty);
  });

  test('calculates partial coverage against recoverable product lines',
      () async {
    final elements = [
      ...fullCoverageElements(),
      receiptElement('price', ReceiptElementType.price, text: '10.00'),
      receiptElement('tax', ReceiptElementType.tax, text: '1.50'),
    ];
    final result = await service.analyze(extractionInput(
      elements: elements,
      lines: [
        extractionLine(id: 'line-1', productId: 'garlic'),
        extractionLine(
          id: 'line-2',
          priceId: 'price',
          completeness: ReceiptLineCompleteness.orphan,
        ),
        extractionLine(
          id: 'line-3',
          taxId: 'tax',
          completeness: ReceiptLineCompleteness.orphan,
        ),
      ],
    ));

    expect(result.metrics.linesContainingProductText, 1);
    expect(result.metrics.linesWithoutProductText, 2);
    expect(result.metrics.recoverableProductLines, 2);
    expect(result.metrics.productTextCoverage, 0.5);
    expect(result.metrics.recoverableProductLinesPercentage,
        closeTo(2 / 3, 0.000001));
    expect(
        result.failureBreakdown[ReceiptExtractionMissingReason.orphanLine], 2);
  });

  test('returns zero-safe metrics for an empty receipt', () async {
    final result = await service.analyze(extractionInput(
      elements: const [],
      lines: const [],
      ocrTexts: const [],
    ));

    expect(result.metrics.ocrTextBlocks, 0);
    expect(result.metrics.receiptElements, 0);
    expect(result.metrics.receiptLines, 0);
    expect(result.metrics.productTextCoverage, 0);
    expect(result.metrics.recoverableProductLinesPercentage, 0);
    expect(result.missingLines, isEmpty);
  });

  test('classifies missing lines with deterministic typed reasons', () async {
    final elements = [
      receiptElement('header', ReceiptElementType.header),
      receiptElement('footer', ReceiptElementType.footer),
      receiptElement('price', ReceiptElementType.price),
      receiptElement(
        'empty-product',
        ReceiptElementType.productName,
        text: '   ',
      ),
    ];
    final result = await service.analyze(extractionInput(
      elements: elements,
      lines: [
        extractionLine(id: 'header-line', priceId: 'header'),
        extractionLine(id: 'footer-line', priceId: 'footer'),
        extractionLine(
          id: 'orphan-line',
          priceId: 'price',
          completeness: ReceiptLineCompleteness.orphan,
        ),
        extractionLine(id: 'empty-line', productId: 'empty-product'),
        extractionLine(id: 'unknown-line'),
      ],
    ));

    expect(
      result.missingLines.map((line) => line.reason),
      [
        ReceiptExtractionMissingReason.headerOnly,
        ReceiptExtractionMissingReason.footerOnly,
        ReceiptExtractionMissingReason.orphanLine,
        ReceiptExtractionMissingReason.unresolvedProductText,
        ReceiptExtractionMissingReason.unknown,
      ],
    );
    expect(result.metrics.emptyProductTextCount, 1);
  });

  test('missing OCR text takes precedence for missing lines', () async {
    final result = await service.analyze(extractionInput(
      elements: [
        receiptElement('price', ReceiptElementType.price),
      ],
      lines: [
        extractionLine(
          id: 'line-1',
          priceId: 'price',
          completeness: ReceiptLineCompleteness.orphan,
        ),
      ],
      ocrTexts: const ['   '],
    ));

    expect(
      result.missingLines.single.reason,
      ReceiptExtractionMissingReason.missingOcrText,
    );
  });

  test('counts duplicate usable product text without altering it', () async {
    final result = await service.analyze(extractionInput(
      elements: [
        receiptElement(
          'first',
          ReceiptElementType.productName,
          text: 'Garlic   Bag',
        ),
        receiptElement(
          'second',
          ReceiptElementType.productName,
          text: ' garlic bag ',
        ),
        receiptElement(
          'third',
          ReceiptElementType.productName,
          text: 'GARLIC BAG',
        ),
      ],
      lines: [
        extractionLine(id: 'line-1', productId: 'first'),
        extractionLine(id: 'line-2', productId: 'second'),
        extractionLine(id: 'line-3', productId: 'third'),
      ],
    ));

    expect(result.metrics.duplicateProductTextCount, 2);
    expect(result.metrics.linesContainingProductText, 3);
  });

  test('result serialization preserves metrics and failures', () async {
    final result = await service.analyze(extractionInput(
      elements: [
        receiptElement('price', ReceiptElementType.price),
      ],
      lines: [
        extractionLine(
          id: 'line-1',
          priceId: 'price',
          completeness: ReceiptLineCompleteness.orphan,
        ),
      ],
    ));

    final restored = ReceiptExtractionBenchmarkResult.fromJson(
      result.toJson(),
    );

    expect(restored.toJson(), result.toJson());
    expect(restored.missingLines.single.reason,
        ReceiptExtractionMissingReason.orphanLine);
  });
}
