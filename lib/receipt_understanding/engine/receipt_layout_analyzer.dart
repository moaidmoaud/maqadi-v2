import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import '../domain/receipt_relative_position.dart';

enum ReceiptReadingDirection { leftToRight, rightToLeft }

class ReceiptDocumentBounds {
  const ReceiptDocumentBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
}

class ReceiptLayoutAnalyzer {
  const ReceiptLayoutAnalyzer();

  List<ReceiptOcrBlock> order(
    List<ReceiptOcrBlock> blocks, {
    required bool preserveOcrOrder,
  }) {
    if (preserveOcrOrder || blocks.length < 2) {
      return List.unmodifiable(blocks);
    }
    final direction = readingDirection(blocks);
    final indexed = <({ReceiptOcrBlock block, int index})>[
      for (var index = 0; index < blocks.length; index++)
        (block: blocks[index], index: index),
    ];
    indexed.sort((left, right) {
      final leftRegion = validRegion(left.block.region);
      final rightRegion = validRegion(right.block.region);
      if (leftRegion == null && rightRegion == null) {
        return left.index.compareTo(right.index);
      }
      if (leftRegion == null) return 1;
      if (rightRegion == null) return -1;
      final vertical = leftRegion.y.compareTo(rightRegion.y);
      if (vertical != 0) return vertical;
      final horizontal = leftRegion.x.compareTo(rightRegion.x);
      if (horizontal != 0) {
        return direction == ReceiptReadingDirection.leftToRight
            ? horizontal
            : -horizontal;
      }
      return left.index.compareTo(right.index);
    });
    return List.unmodifiable(indexed.map((entry) => entry.block));
  }

  ReceiptReadingDirection readingDirection(List<ReceiptOcrBlock> blocks) {
    var arabic = 0;
    var latin = 0;
    for (final rune in blocks.expand((block) => block.text.runes)) {
      if (rune >= 0x0600 && rune <= 0x06ff) {
        arabic++;
      } else if (rune >= 0x0041 && rune <= 0x007a) {
        latin++;
      }
    }
    return arabic > latin
        ? ReceiptReadingDirection.rightToLeft
        : ReceiptReadingDirection.leftToRight;
  }

  ReceiptDocumentBounds? bounds(List<ReceiptOcrBlock> blocks) {
    final regions = blocks
        .map((block) => validRegion(block.region))
        .whereType<ReceiptOcrRegion>()
        .toList(growable: false);
    if (regions.isEmpty) return null;
    var left = regions.first.x < 0 ? regions.first.x : 0.0;
    var top = regions.first.y < 0 ? regions.first.y : 0.0;
    var right = regions.first.x + regions.first.width;
    var bottom = regions.first.y + regions.first.height;
    for (final region in regions.skip(1)) {
      if (region.x < left) left = region.x;
      if (region.y < top) top = region.y;
      if (region.x + region.width > right) right = region.x + region.width;
      if (region.y + region.height > bottom) bottom = region.y + region.height;
    }
    if (right <= left || bottom <= top) return null;
    return ReceiptDocumentBounds(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
  }

  ReceiptRelativePosition relativePosition(
    ReceiptOcrRegion? region,
    ReceiptDocumentBounds? bounds,
  ) {
    final valid = validRegion(region);
    if (valid == null || bounds == null || bounds.height <= 0) {
      return ReceiptRelativePosition.unknown;
    }
    final center = valid.y + (valid.height / 2);
    final normalized = ((center - bounds.top) / bounds.height).clamp(0, 1);
    if (normalized < 0.2) return ReceiptRelativePosition.header;
    if (normalized < 0.8) return ReceiptRelativePosition.body;
    return ReceiptRelativePosition.footer;
  }

  String normalizedRegionKey(
    ReceiptOcrRegion? region,
    ReceiptDocumentBounds? bounds,
  ) {
    final valid = validRegion(region);
    if (valid == null ||
        bounds == null ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return 'none';
    }
    String fixed(double value) => value.toStringAsFixed(6);
    return [
      fixed((valid.x - bounds.left) / bounds.width),
      fixed((valid.y - bounds.top) / bounds.height),
      fixed(valid.width / bounds.width),
      fixed(valid.height / bounds.height),
    ].join(',');
  }

  ReceiptOcrRegion? validRegion(ReceiptOcrRegion? region) {
    if (region == null ||
        !region.x.isFinite ||
        !region.y.isFinite ||
        !region.width.isFinite ||
        !region.height.isFinite ||
        region.width <= 0 ||
        region.height <= 0) {
      return null;
    }
    return region;
  }
}
