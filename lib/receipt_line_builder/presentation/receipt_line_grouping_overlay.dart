import 'package:flutter/material.dart';

import '../../receipt_understanding/domain/receipt_element.dart';
import '../domain/receipt_line.dart';

class ReceiptLineGroupingOverlay extends StatelessWidget {
  const ReceiptLineGroupingOverlay({
    super.key,
    required this.elements,
    required this.lines,
    this.selectedLineId,
  });

  final List<ReceiptElement> elements;
  final List<ReceiptLine> lines;
  final String? selectedLineId;

  @override
  Widget build(BuildContext context) {
    final bounded = {
      for (final element in elements)
        if (element.boundingBox != null) element.id: element,
    };
    if (bounded.isEmpty) {
      return const Center(child: Text('No grouping geometry is available.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        key: const ValueKey('receipt-line-grouping-overlay'),
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _GroupingPainter(
          elements: bounded,
          lines: lines,
          selectedLineId: selectedLineId,
        ),
      ),
    );
  }
}

class _GroupingPainter extends CustomPainter {
  _GroupingPainter({
    required this.elements,
    required this.lines,
    required this.selectedLineId,
  });

  final Map<String, ReceiptElement> elements;
  final List<ReceiptLine> lines;
  final String? selectedLineId;

  @override
  void paint(Canvas canvas, Size size) {
    var right = 1.0;
    var bottom = 1.0;
    for (final element in elements.values) {
      final box = element.boundingBox!;
      if (box.x + box.width > right) right = box.x + box.width;
      if (box.y + box.height > bottom) bottom = box.y + box.height;
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfffafafa),
    );
    Offset center(ReceiptElement element) {
      final box = element.boundingBox!;
      return Offset(
        ((box.x + box.width / 2) / right) * size.width,
        ((box.y + box.height / 2) / bottom) * size.height,
      );
    }

    for (final line in lines) {
      final anchorId = line.productElementId;
      final anchor = anchorId == null ? null : elements[anchorId];
      if (anchor == null) continue;
      final selected = selectedLineId == null || selectedLineId == line.id;
      final paint = Paint()
        ..color = selected ? Colors.teal : Colors.grey.withValues(alpha: 0.35)
        ..strokeWidth = selected ? 2.5 : 1;
      for (final id
          in line.referencedElementIds.where((id) => id != anchorId)) {
        final attached = elements[id];
        if (attached != null) {
          canvas.drawLine(center(anchor), center(attached), paint);
        }
      }
    }
    for (final element in elements.values) {
      final box = element.boundingBox!;
      final rect = Rect.fromLTWH(
        (box.x / right) * size.width,
        (box.y / bottom) * size.height,
        (box.width / right) * size.width,
        (box.height / bottom) * size.height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.blueGrey
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GroupingPainter oldDelegate) =>
      oldDelegate.lines != lines ||
      oldDelegate.elements != elements ||
      oldDelegate.selectedLineId != selectedLineId;
}
