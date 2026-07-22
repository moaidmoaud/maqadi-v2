import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_evidence.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_relative_position.dart';

ReceiptElement receiptElement(
  String id,
  ReceiptElementType type, {
  String? text,
  double x = 0,
  double y = 0,
  double width = 40,
  double height = 10,
  bool withoutGeometry = false,
}) =>
    ReceiptElement(
      id: id,
      text: text ?? id,
      boundingBox: withoutGeometry
          ? null
          : ReceiptOcrRegion(x: x, y: y, width: width, height: height),
      confidence: 0.9,
      type: type,
      evidence: ReceiptElementEvidence(
        matchedRule: 'test-$type',
        normalizedText: (text ?? id).toLowerCase(),
        relativePosition: ReceiptRelativePosition.body,
        neighbourReferences: const [],
        matchedStructuralPatterns: const [],
        ocrConfidence: 0.9,
      ),
    );

List<ReceiptElement> productRow({
  String prefix = 'a',
  double y = 10,
  double scale = 1,
  bool quantity = false,
  bool price = true,
  bool lineTotal = false,
  bool discount = false,
  bool tax = false,
}) =>
    [
      receiptElement(
        '$prefix-product',
        ReceiptElementType.productName,
        x: 0,
        y: y,
        width: 40 * scale,
        height: 10 * scale,
      ),
      if (quantity)
        receiptElement(
          '$prefix-quantity',
          ReceiptElementType.quantity,
          x: 45 * scale,
          y: y,
          width: 10 * scale,
          height: 10 * scale,
        ),
      if (price)
        receiptElement(
          '$prefix-price',
          ReceiptElementType.price,
          x: 60 * scale,
          y: y,
          width: 15 * scale,
          height: 10 * scale,
        ),
      if (lineTotal)
        receiptElement(
          '$prefix-total',
          ReceiptElementType.total,
          x: 78 * scale,
          y: y,
          width: 15 * scale,
          height: 10 * scale,
        ),
      if (discount)
        receiptElement(
          '$prefix-discount',
          ReceiptElementType.discount,
          x: 96 * scale,
          y: y,
          width: 15 * scale,
          height: 10 * scale,
        ),
      if (tax)
        receiptElement(
          '$prefix-tax',
          ReceiptElementType.tax,
          x: 114 * scale,
          y: y,
          width: 15 * scale,
          height: 10 * scale,
        ),
    ];
