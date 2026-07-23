import '../../receipt_line_builder/domain/receipt_line_result.dart';
import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import '../../receipt_understanding/domain/receipt_understanding_result.dart';

class ReceiptExtractionBenchmarkInput {
  const ReceiptExtractionBenchmarkInput({
    required this.receiptId,
    required this.ocrResult,
    required this.understandingResult,
    required this.lineResult,
  });

  final String receiptId;
  final ReceiptOcrResult ocrResult;
  final ReceiptUnderstandingResult understandingResult;
  final ReceiptLineResult lineResult;
}
