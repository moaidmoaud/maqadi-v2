import '../domain/receipt_calibration_policy.dart';
import '../domain/receipt_line_debug_trace.dart';
import 'receipt_line_geometry.dart';

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

class ReceiptSpatialIndexResult {
  ReceiptSpatialIndexResult({
    required Iterable<ReceiptSpatialRow> rows,
    required Iterable<String> canonicalElementOrder,
    required Iterable<ReceiptElementSpatialTrace> elementPlacements,
    required Iterable<ReceiptRowConstructionTrace> rowDecisions,
    required Iterable<ReceiptColumnConstructionTrace> columnDecisions,
  })  : rows = List.unmodifiable(rows),
        canonicalElementOrder = List.unmodifiable(canonicalElementOrder),
        elementPlacements = List.unmodifiable(elementPlacements),
        rowDecisions = List.unmodifiable(rowDecisions),
        columnDecisions = List.unmodifiable(columnDecisions);

  final List<ReceiptSpatialRow> rows;
  final List<String> canonicalElementOrder;
  final List<ReceiptElementSpatialTrace> elementPlacements;
  final List<ReceiptRowConstructionTrace> rowDecisions;
  final List<ReceiptColumnConstructionTrace> columnDecisions;
}

class ReceiptLineSpatialIndex {
  const ReceiptLineSpatialIndex();

  List<ReceiptSpatialRow> organize(
          List<ReceiptLineGeometry> geometries, double medianHeight,
          [ReceiptCalibrationPolicy policy =
              const ReceiptCalibrationPolicy()]) =>
      _organize(
        geometries,
        medianHeight,
        policy,
        includeTrace: false,
      ).rows;

  ReceiptSpatialIndexResult organizeWithTrace(
    List<ReceiptLineGeometry> geometries,
    double medianHeight,
    ReceiptCalibrationPolicy policy,
  ) =>
      _organize(
        geometries,
        medianHeight,
        policy,
        includeTrace: true,
      );

  ReceiptSpatialIndexResult _organize(
    List<ReceiptLineGeometry> geometries,
    double medianHeight,
    ReceiptCalibrationPolicy policy, {
    required bool includeTrace,
  }) {
    if (geometries.isEmpty) {
      return ReceiptSpatialIndexResult(
        rows: const [],
        canonicalElementOrder: const [],
        elementPlacements: const [],
        rowDecisions: const [],
        columnDecisions: const [],
      );
    }
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
    final canonicalIndices = <ReceiptLineGeometry, int>{
      for (var index = 0; index < ordered.length; index++)
        ordered[index]: index,
    };

    final rowValues = <List<ReceiptLineGeometry>>[];
    final rowDecisions = <ReceiptRowConstructionTrace>[];
    var current = <ReceiptLineGeometry>[ordered.first];
    for (final geometry in ordered.skip(1)) {
      final reference = current.last;
      final distance =
          geometry.normalizedVerticalDistance(reference, medianHeight);
      final overlap = geometry.verticalOverlap(reference);
      final joinsRow = distance <= policy.rowVerticalDistanceTolerance ||
          overlap >= policy.rowMinimumOverlapRatio;
      final split = !joinsRow;
      if (includeTrace) {
        rowDecisions.add(ReceiptRowConstructionTrace(
          previousElementId: reference.element.id,
          currentElementId: geometry.element.id,
          normalizedVerticalDistance: distance,
          verticalOverlapRatio: overlap,
          split: split,
          resultingRowIndex: split ? rowValues.length + 1 : rowValues.length,
        ));
      }
      if (joinsRow) {
        current.add(geometry);
      } else {
        rowValues.add(current);
        current = <ReceiptLineGeometry>[geometry];
      }
    }
    rowValues.add(current);

    final columnDecisions = <ReceiptColumnConstructionTrace>[];
    final rows = <ReceiptSpatialRow>[];
    final placements = <ReceiptElementSpatialTrace>[];
    for (var rowIndex = 0; rowIndex < rowValues.length; rowIndex++) {
      final columns = _columns(
        rowValues[rowIndex],
        medianHeight,
        policy,
        rowIndex: rowIndex,
        decisions: includeTrace ? columnDecisions : null,
      );
      rows.add(ReceiptSpatialRow(index: rowIndex, columns: columns));
      if (includeTrace) {
        for (final column in columns) {
          for (final geometry in column.elements) {
            placements.add(ReceiptElementSpatialTrace(
              elementId: geometry.element.id,
              status: ReceiptElementSpatialStatus.placed,
              canonicalIndex: canonicalIndices[geometry],
              rowIndex: rowIndex,
              columnIndex: column.index,
            ));
          }
        }
      }
    }
    if (includeTrace) {
      placements.sort((left, right) =>
          left.canonicalIndex!.compareTo(right.canonicalIndex!));
    }
    return ReceiptSpatialIndexResult(
      rows: rows,
      canonicalElementOrder:
          includeTrace ? ordered.map((value) => value.element.id) : const [],
      elementPlacements: placements,
      rowDecisions: rowDecisions,
      columnDecisions: columnDecisions,
    );
  }

  List<ReceiptSpatialColumn> _columns(
    List<ReceiptLineGeometry> row,
    double medianHeight,
    ReceiptCalibrationPolicy policy, {
    required int rowIndex,
    required List<ReceiptColumnConstructionTrace>? decisions,
  }) {
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
      final split = gap > policy.columnGapTolerance;
      decisions?.add(ReceiptColumnConstructionTrace(
        rowIndex: rowIndex,
        previousElementId: previous.element.id,
        currentElementId: geometry.element.id,
        normalizedHorizontalGap: gap,
        split: split,
        resultingColumnIndex: split ? values.length + 1 : values.length,
      ));
      if (split) {
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
