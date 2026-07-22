import '../../receipt_understanding/domain/receipt_element.dart';

class ReceiptLineGeometry {
  const ReceiptLineGeometry({
    required this.element,
    required this.originalIndex,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory ReceiptLineGeometry.fromElement(
    ReceiptElement element,
    int originalIndex,
  ) {
    final region = element.boundingBox!;
    return ReceiptLineGeometry(
      element: element,
      originalIndex: originalIndex,
      x: region.x,
      y: region.y,
      width: region.width,
      height: region.height,
    );
  }

  final ReceiptElement element;
  final int originalIndex;
  final double x;
  final double y;
  final double width;
  final double height;

  double get left => x;
  double get top => y;
  double get right => x + width;
  double get bottom => y + height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  double normalizedVerticalDistance(
    ReceiptLineGeometry other,
    double medianHeight,
  ) =>
      (centerY - other.centerY).abs() / medianHeight;

  double normalizedHorizontalDistance(
    ReceiptLineGeometry other,
    double medianHeight,
  ) {
    final gap = centerX <= other.centerX
        ? (other.left - right).clamp(0, double.infinity)
        : (left - other.right).clamp(0, double.infinity);
    return gap / medianHeight;
  }

  double verticalOverlap(ReceiptLineGeometry other) {
    final overlap = (bottom < other.bottom ? bottom : other.bottom) -
        (top > other.top ? top : other.top);
    if (overlap <= 0) return 0;
    final shortest = height < other.height ? height : other.height;
    return overlap / shortest;
  }

  static bool hasValidRegion(ReceiptElement element) {
    final region = element.boundingBox;
    if (region == null ||
        !region.x.isFinite ||
        !region.y.isFinite ||
        !region.width.isFinite ||
        !region.height.isFinite ||
        region.width <= 0 ||
        region.height <= 0) {
      return false;
    }
    return true;
  }

  static double? medianPositiveHeight(Iterable<ReceiptLineGeometry> values) {
    final heights = values
        .map((value) => value.height)
        .where((height) => height.isFinite && height > 0)
        .toList()
      ..sort();
    if (heights.isEmpty) return null;
    final middle = heights.length ~/ 2;
    if (heights.length.isOdd) return heights[middle];
    return (heights[middle - 1] + heights[middle]) / 2;
  }
}
