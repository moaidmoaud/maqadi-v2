import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import 'receipt_element_evidence.dart';
import 'receipt_element_type.dart';

class ReceiptElement {
  const ReceiptElement({
    required this.id,
    required this.text,
    required this.boundingBox,
    required this.confidence,
    required this.type,
    required this.evidence,
  });

  final String id;
  final String text;
  final ReceiptOcrRegion? boundingBox;
  final double? confidence;
  final ReceiptElementType type;
  final ReceiptElementEvidence evidence;
}
