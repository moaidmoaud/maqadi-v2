import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_relative_position.dart';
import 'package:maqadi_v2/receipt_understanding/engine/receipt_element_id_generator.dart';
import 'package:maqadi_v2/receipt_understanding/engine/receipt_layout_analyzer.dart';
import 'package:maqadi_v2/receipt_understanding/engine/receipt_text_normalizer.dart';
import 'package:maqadi_v2/receipt_understanding/engine/receipt_understanding_engine.dart';

import 'receipt_understanding_test_support.dart';

void main() {
  const normalizer = ReceiptTextNormalizer();
  const layout = ReceiptLayoutAnalyzer();
  const ids = ReceiptElementIdGenerator();
  const engine = ReceiptUnderstandingEngine();

  test('normalizes English, Arabic variants, and whitespace', () {
    expect(normalizer.normalize('  GRAND   TOTAL  '), 'grand total');
    expect(normalizer.normalize('إجْمَـالي'), 'اجمـالي');
    expect(normalizer.normalize('آلية مؤقتة'), 'اليه موقته');
  });

  test('normalizes digits while preserving financial punctuation', () {
    expect(normalizer.normalize('−١٢٫٥٠ ر.س %'), '-12.50 ر.س %');
    expect(normalizer.normalize('۱۲٬۳۴۵٫۶۷'), '12,345.67');
  });

  test('preserves guaranteed OCR order', () {
    final blocks = [ocrBlock('bottom', y: 90), ocrBlock('top', y: 5)];
    expect(
      layout.order(blocks, preserveOcrOrder: true).map((block) => block.text),
      ['bottom', 'top'],
    );
  });

  test('spatially orders LTR blocks top-to-bottom then left-to-right', () {
    final blocks = [
      ocrBlock('right', x: 60, y: 10),
      ocrBlock('bottom', x: 0, y: 20),
      ocrBlock('left', x: 0, y: 10),
    ];
    expect(
      layout.order(blocks, preserveOcrOrder: false).map((block) => block.text),
      ['left', 'right', 'bottom'],
    );
  });

  test('spatially orders Arabic blocks right-to-left', () {
    final blocks = [
      ocrBlock('يسار', x: 0, y: 10),
      ocrBlock('يمين', x: 60, y: 10),
    ];
    expect(
      layout.order(blocks, preserveOcrOrder: false).map((block) => block.text),
      ['يمين', 'يسار'],
    );
  });

  test('places missing geometry deterministically after bounded blocks', () {
    final blocks = [
      ocrBlock('unbounded', withoutRegion: true),
      ocrBlock('bounded', y: 10),
      ocrBlock('unbounded two', withoutRegion: true),
    ];
    expect(
      layout.order(blocks, preserveOcrOrder: false).map((block) => block.text),
      ['bounded', 'unbounded', 'unbounded two'],
    );
  });

  test('uses exact twenty and eighty percent zone boundaries', () {
    const bounds = ReceiptDocumentBounds(
      left: 0,
      top: 0,
      right: 100,
      bottom: 100,
    );
    expect(
      layout.relativePosition(
        const ReceiptOcrRegion(x: 0, y: 15, width: 10, height: 10),
        bounds,
      ),
      ReceiptRelativePosition.body,
    );
    expect(
      layout.relativePosition(
        const ReceiptOcrRegion(x: 0, y: 75, width: 10, height: 10),
        bounds,
      ),
      ReceiptRelativePosition.footer,
    );
  });

  test('missing geometry has Unknown relative position', () {
    expect(
      layout.relativePosition(null, null),
      ReceiptRelativePosition.unknown,
    );
  });

  test('stable FNV IDs repeat for identical normalized keys', () {
    final first = ids.baseId(normalizedText: 'total', regionKey: '0,0,1,1');
    final second = ids.baseId(normalizedText: 'total', regionKey: '0,0,1,1');
    expect(first, second);
    expect(first, matches(RegExp(r'^[0-9a-f]{16}$')));
  });

  test('duplicate stable IDs receive deterministic occurrence suffixes', () {
    final generated = ids.generate(const [
      (text: 'same', regionKey: 'none'),
      (text: 'same', regionKey: 'none'),
      (text: 'same', regionKey: 'none'),
    ]);
    expect(generated[1], '${generated[0]}-1');
    expect(generated[2], '${generated[0]}-2');
  });

  test('produces exactly one immutable element per OCR block', () {
    final blocks = [ocrBlock('A'), ocrBlock('B'), ocrBlock('C')];
    final elements = engine.classify(blocks);
    expect(elements, hasLength(blocks.length));
    expect(() => elements.add(elements.first), throwsUnsupportedError);
  });

  test('classifies structural total', () {
    final element =
        engine.classify(receiptWith(ocrBlock('TOTAL 12.50', y: 60)))[1];
    expect(element.type, ReceiptElementType.total);
  });

  test('classifies structural tax', () {
    final element = engine.classify(receiptWith(ocrBlock('VAT 15%', y: 60)))[1];
    expect(element.type, ReceiptElementType.tax);
  });

  test('classifies structural discount', () {
    final element =
        engine.classify(receiptWith(ocrBlock('DISCOUNT -2.00', y: 60)))[1];
    expect(element.type, ReceiptElementType.discount);
  });

  test('classifies structural quantity before a monetary pattern', () {
    final element =
        engine.classify(receiptWith(ocrBlock('QTY 2 x 3.00', y: 50)))[1];
    expect(element.type, ReceiptElementType.quantity);
  });

  test('classifies a generic decimal monetary value as Price', () {
    final element = engine.classify(receiptWith(ocrBlock('12.50', y: 50)))[1];
    expect(element.type, ReceiptElementType.price);
  });

  test('classifies receipt date as Metadata before positional types', () {
    final element =
        engine.classify(receiptWith(ocrBlock('DATE 2026/07/22', y: 50)))[1];
    expect(element.type, ReceiptElementType.metadata);
  });

  test('selects one structurally prominent top-zone StoreName', () {
    final elements = engine.classify([
      ocrBlock('SMALL HEADER', x: 20, y: 2, width: 40, height: 3),
      ocrBlock('PROMINENT TEXT', x: 5, y: 8, width: 90, height: 8),
      ocrBlock('12.50', y: 50),
      ocrBlock('THANK YOU', y: 95),
    ]);
    expect(elements.where((e) => e.type == ReceiptElementType.storeName),
        hasLength(1));
    expect(elements[1].type, ReceiptElementType.storeName);
  });

  test('classifies remaining top-zone text as Header', () {
    final elements = engine.classify([
      ocrBlock('PROMINENT TEXT', x: 5, y: 2, width: 90, height: 8),
      ocrBlock('WELCOME', x: 20, y: 12, width: 40, height: 3),
      ocrBlock('12.50', y: 50),
      ocrBlock('THANK YOU', y: 95),
    ]);
    expect(elements[1].type, ReceiptElementType.header);
  });

  test('classifies bottom-zone closing text as Footer', () {
    final element =
        engine.classify(receiptWith(ocrBlock('VISIT AGAIN', y: 95)))[1];
    expect(element.type, ReceiptElementType.footer);
  });

  test('classifies body text adjacent to a price as structural ProductName',
      () {
    final elements = engine.classify([
      ocrBlock('RECEIPT', y: 0),
      ocrBlock('BODY DESCRIPTION', x: 0, y: 45),
      ocrBlock('12.50', x: 80, y: 45, width: 20),
      ocrBlock('THANK YOU', y: 95),
    ]);
    expect(elements[1].type, ReceiptElementType.productName);
  });

  test('uses Unknown as the safe fallback', () {
    final element = engine.classify([
      ocrBlock('???', withoutRegion: true),
    ]).single;
    expect(element.type, ReceiptElementType.unknown);
  });

  test('Total precedence wins over generic Price', () {
    final element =
        engine.classify(receiptWith(ocrBlock('TOTAL SAR 12.50', y: 50)))[1];
    expect(element.type, ReceiptElementType.total);
    expect(element.evidence.matchedRule, 'total');
  });

  test('supports mixed Arabic and English structural terms', () {
    final elements = engine.classify([
      ocrBlock('RECEIPT', y: 0),
      ocrBlock('الضريبة VAT 15%', y: 45),
      ocrBlock('الإجمالي ١٢٫٥٠', y: 60),
      ocrBlock('شكراً', y: 95),
    ]);
    expect(elements[1].type, ReceiptElementType.tax);
    expect(elements[2].type, ReceiptElementType.total);
    expect(elements[3].type, ReceiptElementType.footer);
  });

  test('OCR confidence never changes classification', () {
    final low = engine.classify(receiptWith(
      ocrBlock('TOTAL 12.50', y: 50, confidence: 0.01),
    ))[1];
    final high = engine.classify(receiptWith(
      ocrBlock('TOTAL 12.50', y: 50, confidence: 0.99),
    ))[1];
    expect(low.type, high.type);
    expect(low.type, ReceiptElementType.total);
  });

  test('missing OCR confidence remains nullable evidence', () {
    final element = engine.classify([
      ocrBlock('TOTAL', confidence: null),
    ]).single;
    expect(element.confidence, isNull);
    expect(element.evidence.ocrConfidence, isNull);
  });

  test('generates complete structured classification evidence', () {
    final elements = engine.classify(receiptWith(ocrBlock('TOTAL', y: 50)));
    final element = elements[1];
    expect(element.evidence.normalizedText, 'total');
    expect(element.evidence.relativePosition, ReceiptRelativePosition.body);
    expect(element.evidence.neighbourReferences, hasLength(2));
    expect(element.evidence.matchedStructuralPatterns, contains('total'));
    expect(element.evidence.summary, isNotEmpty);
  });

  test('classification and IDs are deterministic for identical blocks', () {
    final blocks = receiptWith(ocrBlock('TOTAL 12.50', y: 50));
    final first = engine.classify(blocks);
    final second = engine.classify(blocks);
    expect(second.map((e) => e.id), first.map((e) => e.id));
    expect(second.map((e) => e.type), first.map((e) => e.type));
  });

  test('preserves original OCR text while classifying normalized text', () {
    final element = engine.classify([
      ocrBlock('  الإجمالي ١٢٫٥٠  '),
    ]).single;
    expect(element.text, '  الإجمالي ١٢٫٥٠  ');
    expect(element.evidence.normalizedText, 'الاجمالي 12.50');
  });

  test('short single-block receipt is classified without splitting', () {
    final elements = engine.classify([ocrBlock('TOTAL 5.00')]);
    expect(elements, hasLength(1));
    expect(elements.single.type, ReceiptElementType.total);
  });
}
