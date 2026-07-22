import 'package:flutter/material.dart';

import '../domain/receipt_benchmark_definition.dart';
import '../domain/receipt_benchmark_result.dart';

enum ReceiptBenchmarkOverlayMode { expected, actual, mismatches }

class ReceiptBenchmarkOverlay extends StatelessWidget {
  const ReceiptBenchmarkOverlay({
    super.key,
    required this.result,
    required this.mode,
  });

  final ReceiptBenchmarkResult result;
  final ReceiptBenchmarkOverlayMode mode;

  @override
  Widget build(BuildContext context) {
    final bounded = {
      for (final block in result.definition.fixtureBlocks)
        if (block.region != null) block.fixtureKey: block,
    };
    if (bounded.isEmpty) {
      return const Center(child: Text('No benchmark geometry is available.'));
    }
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        key: ValueKey('receipt-benchmark-overlay-${mode.name}'),
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: _BenchmarkOverlayPainter(
          blocks: bounded,
          result: result,
          mode: mode,
        ),
      ),
    );
  }
}

class _BenchmarkOverlayPainter extends CustomPainter {
  _BenchmarkOverlayPainter({
    required this.blocks,
    required this.result,
    required this.mode,
  });

  final Map<String, ReceiptBenchmarkFixtureBlock> blocks;
  final ReceiptBenchmarkResult result;
  final ReceiptBenchmarkOverlayMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    var right = 1.0;
    var bottom = 1.0;
    for (final block in blocks.values) {
      final region = block.region!;
      if (region.x + region.width > right) right = region.x + region.width;
      if (region.y + region.height > bottom) bottom = region.y + region.height;
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xfffafafa),
    );
    Offset center(String key) {
      final region = blocks[key]!.region!;
      return Offset(
        ((region.x + region.width / 2) / right) * size.width,
        ((region.y + region.height / 2) / bottom) * size.height,
      );
    }

    final mismatchKeys = _mismatchKeys();
    final expectedUnassigned =
        result.definition.groundTruth.expectedUnassignedKeys.toSet();
    final actualUnassigned = result.actualLines.unassignedElements
        .map((element) => result.actualElementIdToFixtureKey[element.elementId])
        .whereType<String>()
        .toSet();
    for (final block in blocks.values) {
      final region = block.region!;
      final rect = Rect.fromLTWH(
        (region.x / right) * size.width,
        (region.y / bottom) * size.height,
        (region.width / right) * size.width,
        (region.height / bottom) * size.height,
      );
      final color = switch (mode) {
        ReceiptBenchmarkOverlayMode.mismatches
            when mismatchKeys.contains(block.fixtureKey) =>
          Colors.red,
        ReceiptBenchmarkOverlayMode.expected
            when expectedUnassigned.contains(block.fixtureKey) =>
          Colors.orange,
        ReceiptBenchmarkOverlayMode.actual
            when actualUnassigned.contains(block.fixtureKey) =>
          Colors.orange,
        ReceiptBenchmarkOverlayMode.expected => Colors.green,
        ReceiptBenchmarkOverlayMode.actual => Colors.blue,
        ReceiptBenchmarkOverlayMode.mismatches => Colors.blue,
      };
      canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    final lineRoles = mode == ReceiptBenchmarkOverlayMode.expected
        ? result.definition.groundTruth.expectedLines.map((line) => line.roles)
        : result.actualLines.lines.map(result.actualRoles);
    for (final roles in lineRoles) {
      final anchor = roles['product'];
      if (anchor == null || !blocks.containsKey(anchor)) continue;
      for (final key in roles.values.whereType<String>()) {
        if (key != anchor && blocks.containsKey(key)) {
          canvas.drawLine(
            center(anchor),
            center(key),
            Paint()
              ..color = mode == ReceiptBenchmarkOverlayMode.expected
                  ? Colors.green
                  : Colors.blue
              ..strokeWidth = 2,
          );
        }
      }
    }
  }

  Set<String> _mismatchKeys() => {
        ...result.understanding.misclassifiedElements
            .map((value) => value.fixtureKey),
        ...result.understanding.missingExpectedElements,
        for (final mismatch in result.lines.incorrectRoleAttachments) ...[
          if (mismatch.expectedElementKey != null) mismatch.expectedElementKey!,
          if (mismatch.actualElementKey != null) mismatch.actualElementKey!,
        ],
        ...result.lines.missingExpectedUnassigned,
        ...result.lines.unexpectedUnassigned,
      };

  @override
  bool shouldRepaint(covariant _BenchmarkOverlayPainter oldDelegate) =>
      oldDelegate.result != result || oldDelegate.mode != mode;
}
