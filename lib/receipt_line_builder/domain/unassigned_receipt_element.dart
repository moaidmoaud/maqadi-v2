import 'receipt_line_evidence.dart';

enum UnassignedReceiptElementReason {
  excludedElementType,
  geometryUnavailable,
}

class UnassignedReceiptElement {
  const UnassignedReceiptElement({
    required this.elementId,
    required this.reasonCode,
    required this.evidence,
  });

  final String elementId;
  final UnassignedReceiptElementReason reasonCode;
  final ReceiptLineEvidence evidence;
}
