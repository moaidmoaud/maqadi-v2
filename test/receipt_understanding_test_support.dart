import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';

ReceiptOcrBlock ocrBlock(
  String text, {
  double x = 0,
  double y = 0,
  double width = 80,
  double height = 5,
  double? confidence = 0.9,
  bool withoutRegion = false,
}) =>
    ReceiptOcrBlock(
      text: text,
      lines: const [],
      confidence: confidence,
      region: withoutRegion
          ? null
          : ReceiptOcrRegion(x: x, y: y, width: width, height: height),
    );

ReceiptOcrResult ocrResult(
  List<ReceiptOcrBlock> blocks, {
  String? text,
}) =>
    ReceiptOcrResult(
      text: text ?? blocks.map((block) => block.text).join('\n'),
      blocks: blocks,
    );

List<ReceiptOcrBlock> receiptWith(
  ReceiptOcrBlock target, {
  bool includeTopAnchor = true,
  bool includeBottomAnchor = true,
}) =>
    [
      if (includeTopAnchor) ocrBlock('RECEIPT', y: 0, height: 2),
      target,
      if (includeBottomAnchor) ocrBlock('THANK YOU', y: 95, height: 5),
    ];
