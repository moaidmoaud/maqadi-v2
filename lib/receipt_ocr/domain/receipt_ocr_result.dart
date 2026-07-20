class ReceiptOcrRegion {
  const ReceiptOcrRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

class ReceiptOcrWord {
  const ReceiptOcrWord({
    required this.text,
    this.confidence,
    this.region,
  });

  final String text;
  final double? confidence;
  final ReceiptOcrRegion? region;
}

class ReceiptOcrLine {
  const ReceiptOcrLine({
    required this.text,
    required this.words,
    this.confidence,
    this.region,
  });

  final String text;
  final List<ReceiptOcrWord> words;
  final double? confidence;
  final ReceiptOcrRegion? region;
}

class ReceiptOcrBlock {
  const ReceiptOcrBlock({
    required this.text,
    required this.lines,
    this.confidence,
    this.region,
  });

  final String text;
  final List<ReceiptOcrLine> lines;
  final double? confidence;
  final ReceiptOcrRegion? region;
}

class ReceiptOcrResult {
  const ReceiptOcrResult({
    required this.text,
    required this.blocks,
    this.confidence,
    this.region,
  });

  final String text;
  final List<ReceiptOcrBlock> blocks;
  final double? confidence;
  final ReceiptOcrRegion? region;
}
