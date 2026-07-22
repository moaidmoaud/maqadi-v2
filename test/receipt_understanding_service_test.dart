import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_understanding/application/receipt_understanding_service.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_understanding_failure.dart';
import 'package:maqadi_v2/receipt_understanding/engine/receipt_understanding_engine.dart';

import 'receipt_understanding_test_support.dart';

void main() {
  test('invokes the engine once and preserves guaranteed OCR order', () async {
    final engine = _CountingEngine();
    final blocks = [ocrBlock('TOTAL', y: 90), ocrBlock('DATE', y: 5)];
    final result = await ReceiptUnderstandingService(engine: engine).understand(
      ocrResult(blocks),
      ocrReadingOrderGuaranteed: true,
    );
    expect(engine.calls, 1);
    expect(result.elements.map((element) => element.text), ['TOTAL', 'DATE']);
    expect(result.ocrOrderPreserved, isTrue);
  });

  test('spatially sorts OCR blocks when order is not guaranteed', () async {
    final blocks = [ocrBlock('TOTAL', y: 90), ocrBlock('DATE', y: 5)];
    final result = await const ReceiptUnderstandingService().understand(
      ocrResult(blocks),
    );
    expect(result.elements.map((element) => element.text), ['DATE', 'TOTAL']);
    expect(result.ocrOrderPreserved, isFalse);
  });

  test('returns an immutable empty result for empty OCR', () async {
    final result = await const ReceiptUnderstandingService().understand(
      const ReceiptOcrResult(text: '', blocks: []),
    );
    expect(result.elements, isEmpty);
    expect(() => result.elements.addAll(const []), throwsUnsupportedError);
  });

  test('maps unexpected engine exceptions to a domain failure', () async {
    await expectLater(
      ReceiptUnderstandingService(engine: _ThrowingEngine()).understand(
        ocrResult([ocrBlock('TOTAL')]),
      ),
      throwsA(
        isA<ReceiptUnderstandingFailure>().having(
          (failure) => failure.code,
          'code',
          ReceiptUnderstandingFailureCode.classificationFailed,
        ),
      ),
    );
  });

  test('rejects an engine that violates one-block-to-one-element output',
      () async {
    await expectLater(
      ReceiptUnderstandingService(engine: _DroppingEngine()).understand(
        ocrResult([ocrBlock('TOTAL')]),
      ),
      throwsA(
        isA<ReceiptUnderstandingFailure>().having(
          (failure) => failure.message,
          'message',
          contains('one-to-one'),
        ),
      ),
    );
  });

  test('accepts missing geometry and confidence', () async {
    final result = await const ReceiptUnderstandingService().understand(
      ocrResult([
        ocrBlock('TOTAL', withoutRegion: true, confidence: null),
      ]),
    );
    expect(result.elements.single.boundingBox, isNull);
    expect(result.elements.single.confidence, isNull);
  });

  test('does not mutate the OCR block collection', () async {
    final blocks = [ocrBlock('TOTAL', y: 90), ocrBlock('DATE', y: 5)];
    final original = List<ReceiptOcrBlock>.from(blocks);
    await const ReceiptUnderstandingService().understand(ocrResult(blocks));
    expect(blocks, orderedEquals(original));
  });

  test('classifies a large receipt with one element per block', () async {
    final blocks = [
      for (var index = 0; index < 10000; index++)
        ocrBlock(
          index.isEven ? 'ITEM $index' : '${index / 100}.00',
          y: index.toDouble(),
        ),
    ];
    final result = await const ReceiptUnderstandingService().understand(
      ocrResult(blocks),
      ocrReadingOrderGuaranteed: true,
    );
    expect(result.elements, hasLength(10000));
    expect(
        result.elements.map((element) => element.id).toSet(), hasLength(10000));
  });
}

class _CountingEngine extends ReceiptUnderstandingEngine {
  int calls = 0;

  @override
  List<ReceiptElement> classify(List<ReceiptOcrBlock> orderedBlocks) {
    calls++;
    return super.classify(orderedBlocks);
  }
}

class _ThrowingEngine extends ReceiptUnderstandingEngine {
  @override
  List<ReceiptElement> classify(List<ReceiptOcrBlock> orderedBlocks) =>
      throw StateError('classification failed');
}

class _DroppingEngine extends ReceiptUnderstandingEngine {
  @override
  List<ReceiptElement> classify(List<ReceiptOcrBlock> orderedBlocks) =>
      const [];
}
