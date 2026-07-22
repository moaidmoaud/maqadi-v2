import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import '../domain/receipt_understanding_failure.dart';
import '../domain/receipt_understanding_result.dart';
import '../engine/receipt_layout_analyzer.dart';
import '../engine/receipt_understanding_engine.dart';

class ReceiptUnderstandingService {
  const ReceiptUnderstandingService({
    ReceiptUnderstandingEngine engine = const ReceiptUnderstandingEngine(),
    ReceiptLayoutAnalyzer layoutAnalyzer = const ReceiptLayoutAnalyzer(),
  })  : _engine = engine,
        _layoutAnalyzer = layoutAnalyzer;

  final ReceiptUnderstandingEngine _engine;
  final ReceiptLayoutAnalyzer _layoutAnalyzer;

  Future<ReceiptUnderstandingResult> understand(
    ReceiptOcrResult ocrResult, {
    bool ocrReadingOrderGuaranteed = false,
  }) async {
    if (ocrResult.text.trim().isEmpty &&
        ocrResult.blocks.every((block) => block.text.trim().isEmpty)) {
      return ReceiptUnderstandingResult(
        elements: const [],
        ocrOrderPreserved: ocrReadingOrderGuaranteed,
      );
    }
    try {
      final ordered = _layoutAnalyzer.order(
        ocrResult.blocks,
        preserveOcrOrder: ocrReadingOrderGuaranteed,
      );
      final elements = _engine.classify(ordered);
      if (elements.length != ocrResult.blocks.length) {
        throw const ReceiptUnderstandingFailure(
          code: ReceiptUnderstandingFailureCode.classificationFailed,
          message: 'Receipt blocks were not classified one-to-one.',
        );
      }
      return ReceiptUnderstandingResult(
        elements: elements,
        ocrOrderPreserved: ocrReadingOrderGuaranteed,
      );
    } on ReceiptUnderstandingFailure {
      rethrow;
    } catch (error) {
      throw ReceiptUnderstandingFailure(
        code: ReceiptUnderstandingFailureCode.classificationFailed,
        message: 'Receipt structure could not be classified.',
        cause: error,
      );
    }
  }
}
