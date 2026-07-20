import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/receipt_ocr_result.dart';

class MlKitOcrResultMapper {
  const MlKitOcrResultMapper();

  ReceiptOcrResult map(RecognizedText source) => ReceiptOcrResult(
        text: source.text,
        blocks: source.blocks.map(_mapBlock).toList(growable: false),
      );

  ReceiptOcrBlock _mapBlock(TextBlock source) => ReceiptOcrBlock(
        text: source.text,
        lines: source.lines.map(_mapLine).toList(growable: false),
        region: _mapRegion(source.boundingBox),
      );

  ReceiptOcrLine _mapLine(TextLine source) => ReceiptOcrLine(
        text: source.text,
        words: source.elements.map(_mapWord).toList(growable: false),
        confidence: source.confidence,
        region: _mapRegion(source.boundingBox),
      );

  ReceiptOcrWord _mapWord(TextElement source) => ReceiptOcrWord(
        text: source.text,
        confidence: source.confidence,
        region: _mapRegion(source.boundingBox),
      );

  ReceiptOcrRegion _mapRegion(Rect source) => ReceiptOcrRegion(
        x: source.left,
        y: source.top,
        width: source.width,
        height: source.height,
      );
}
