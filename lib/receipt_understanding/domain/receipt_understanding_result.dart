import 'receipt_element.dart';

class ReceiptUnderstandingResult {
  ReceiptUnderstandingResult({
    required Iterable<ReceiptElement> elements,
    required this.ocrOrderPreserved,
  }) : elements = List.unmodifiable(elements);

  final List<ReceiptElement> elements;
  final bool ocrOrderPreserved;
}
