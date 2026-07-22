import 'receipt_line_completeness.dart';
import 'receipt_line_evidence.dart';

class ReceiptLine {
  const ReceiptLine({
    required this.id,
    required this.productElementId,
    required this.priceElementId,
    required this.quantityElementId,
    required this.discountElementId,
    required this.taxElementId,
    required this.lineTotalElementId,
    required this.completeness,
    required this.evidence,
  });

  final String id;
  final String? productElementId;
  final String? priceElementId;
  final String? quantityElementId;
  final String? discountElementId;
  final String? taxElementId;
  final String? lineTotalElementId;
  final ReceiptLineCompleteness completeness;
  final ReceiptLineEvidence evidence;

  List<String> get referencedElementIds => List.unmodifiable([
        productElementId,
        priceElementId,
        quantityElementId,
        discountElementId,
        taxElementId,
        lineTotalElementId,
      ].whereType<String>());
}
