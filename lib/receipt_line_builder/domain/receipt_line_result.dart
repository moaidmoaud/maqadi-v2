import 'receipt_line.dart';
import 'receipt_line_failure.dart';
import 'unassigned_receipt_element.dart';

class ReceiptLineResult {
  ReceiptLineResult({
    required Iterable<ReceiptLine> lines,
    required Iterable<UnassignedReceiptElement> unassignedElements,
    required Iterable<ReceiptLineFailure> failures,
  })  : lines = List.unmodifiable(lines),
        unassignedElements = List.unmodifiable(unassignedElements),
        failures = List.unmodifiable(failures);

  final List<ReceiptLine> lines;
  final List<UnassignedReceiptElement> unassignedElements;
  final List<ReceiptLineFailure> failures;
}
