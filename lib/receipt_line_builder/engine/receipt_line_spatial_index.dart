import 'receipt_line_geometry.dart';
import 'receipt_line_grouping_rules.dart';

class ReceiptSpatialColumn {
  ReceiptSpatialColumn({
    required this.index,
    required Iterable<ReceiptLineGeometry> elements,
  }) : elements = List.unmodifiable(elements);

  final int index;
  final List<ReceiptLineGeometry> elements;
}

class ReceiptSpatialRow {
  ReceiptSpatialRow({
    required this.index,
    required Iterable<ReceiptSpatialColumn> columns,
  }) : columns = List.unmodifiable(columns);

  final int index;
  final List<ReceiptSpatialColumn> columns;
}

class ReceiptLineSpatialIndex {
  const ReceiptLineSpatialIndex();

  List<ReceiptSpatialRow> organize(
    List<ReceiptLineGeometry> geometries,
    double medianHeight,
  ) {
    if (geometries.isEmpty) return const [];
    final ordered = List<ReceiptLineGeometry>.from(geometries)
      ..sort((left, right) {
        final vertical = left.centerY.compareTo(right.centerY);
        if (vertical != 0) return vertical;
        final horizontal = left.centerX.compareTo(right.centerX);
        if (horizontal != 0) return horizontal;
        final original = left.originalIndex.compareTo(right.originalIndex);
        if (original != 0) return original;
        return left.element.id.compareTo(right.element.id);
      });

    final rowValues = <List<ReceiptLineGeometry>>[];
    var current = <ReceiptLineGeometry>[ordered.first];
    for (final geometry in ordered.skip(1)) {
      final reference = current.last;
      final distance =
          geometry.normalizedVerticalDistance(reference, medianHeight);
      final overlap = geometry.verticalOverlap(reference);
      if (distance <= ReceiptLineGroupingRules.maximumNormalizedRowDistance ||
          overlap >= ReceiptLineGroupingRules.minimumVerticalOverlap) {
        current.add(geometry);
      } else {
        rowValues.add(current);
        current = <ReceiptLineGeometry>[geometry];
      }
    }
    rowValues.add(current);

    return List.unmodifiable([
      for (var rowIndex = 0; rowIndex < rowValues.length; rowIndex++)
        ReceiptSpatialRow(
          index: rowIndex,
          columns: _columns(rowValues[rowIndex], medianHeight),
        ),
    ]);
  }

  List<ReceiptSpatialColumn> _columns(
    List<ReceiptLineGeometry> row,
    double medianHeight,
  ) {
    final ordered = List<ReceiptLineGeometry>.from(row)
      ..sort((left, right) {
        final horizontal = left.left.compareTo(right.left);
        if (horizontal != 0) return horizontal;
        return left.originalIndex.compareTo(right.originalIndex);
      });
    final values = <List<ReceiptLineGeometry>>[];
    var current = <ReceiptLineGeometry>[ordered.first];
    for (final geometry in ordered.skip(1)) {
      final previous = current.last;
      final gap = (geometry.left - previous.right).clamp(0, double.infinity) /
          medianHeight;
      if (gap > ReceiptLineGroupingRules.columnBreakNormalizedGap) {
        values.add(current);
        current = <ReceiptLineGeometry>[geometry];
      } else {
        current.add(geometry);
      }
    }
    values.add(current);
    return List.unmodifiable([
      for (var index = 0; index < values.length; index++)
        ReceiptSpatialColumn(index: index, elements: values[index]),
    ]);
  }
}
