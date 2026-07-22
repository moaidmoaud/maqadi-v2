import 'package:flutter/material.dart';

import '../domain/receipt_element.dart';
import '../domain/receipt_element_type.dart';

class ReceiptBoundingBoxOverlay extends StatelessWidget {
  const ReceiptBoundingBoxOverlay({
    super.key,
    required this.elements,
  });

  final List<ReceiptElement> elements;

  @override
  Widget build(BuildContext context) {
    final bounded = elements
        .where((element) => element.boundingBox != null)
        .toList(growable: false);
    if (bounded.isEmpty) {
      return const Center(
        child: Text('No bounding boxes are available.'),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        key: const ValueKey('receipt-understanding-overlay'),
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _ReceiptOverlayPainter(bounded),
      ),
    );
  }
}

class _ReceiptOverlayPainter extends CustomPainter {
  _ReceiptOverlayPainter(this.elements);

  final List<ReceiptElement> elements;

  @override
  void paint(Canvas canvas, Size size) {
    var right = 1.0;
    var bottom = 1.0;
    for (final element in elements) {
      final region = element.boundingBox!;
      if (region.x + region.width > right) right = region.x + region.width;
      if (region.y + region.height > bottom) bottom = region.y + region.height;
    }
    final background = Paint()..color = const Color(0xfffafafa);
    canvas.drawRect(Offset.zero & size, background);
    for (final element in elements) {
      final region = element.boundingBox!;
      final rect = Rect.fromLTWH(
        (region.x / right) * size.width,
        (region.y / bottom) * size.height,
        (region.width / right) * size.width,
        (region.height / bottom) * size.height,
      );
      final color = _color(element.type);
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final label = TextPainter(
        text: TextSpan(
          text: element.type.name,
          style: TextStyle(color: color, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: rect.width < 20 ? 20 : rect.width);
      label.paint(
          canvas, Offset(rect.left, (rect.top - 12).clamp(0, size.height)));
    }
  }

  Color _color(ReceiptElementType type) => switch (type) {
        ReceiptElementType.unknown => Colors.grey,
        ReceiptElementType.storeName => Colors.deepPurple,
        ReceiptElementType.header => Colors.indigo,
        ReceiptElementType.productName => Colors.teal,
        ReceiptElementType.price => Colors.green,
        ReceiptElementType.quantity => Colors.cyan,
        ReceiptElementType.discount => Colors.orange,
        ReceiptElementType.tax => Colors.amber,
        ReceiptElementType.total => Colors.red,
        ReceiptElementType.metadata => Colors.blueGrey,
        ReceiptElementType.footer => Colors.brown,
      };

  @override
  bool shouldRepaint(covariant _ReceiptOverlayPainter oldDelegate) =>
      oldDelegate.elements != elements;
}
