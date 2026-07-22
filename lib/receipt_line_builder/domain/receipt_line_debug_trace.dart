import 'receipt_calibration_policy.dart';
import 'receipt_line_completeness.dart';

enum ReceiptElementSpatialStatus { placed, geometryUnavailable }

class ReceiptElementSpatialTrace {
  const ReceiptElementSpatialTrace({
    required this.elementId,
    required this.status,
    required this.canonicalIndex,
    required this.rowIndex,
    required this.columnIndex,
  });

  final String elementId;
  final ReceiptElementSpatialStatus status;
  final int? canonicalIndex;
  final int? rowIndex;
  final int? columnIndex;
}

class ReceiptRowConstructionTrace {
  const ReceiptRowConstructionTrace({
    required this.previousElementId,
    required this.currentElementId,
    required this.normalizedVerticalDistance,
    required this.verticalOverlapRatio,
    required this.split,
    required this.resultingRowIndex,
  });

  final String previousElementId;
  final String currentElementId;
  final double normalizedVerticalDistance;
  final double verticalOverlapRatio;
  final bool split;
  final int resultingRowIndex;
}

class ReceiptColumnConstructionTrace {
  const ReceiptColumnConstructionTrace({
    required this.rowIndex,
    required this.previousElementId,
    required this.currentElementId,
    required this.normalizedHorizontalGap,
    required this.split,
    required this.resultingColumnIndex,
  });

  final int rowIndex;
  final String previousElementId;
  final String currentElementId;
  final double normalizedHorizontalGap;
  final bool split;
  final int resultingColumnIndex;
}

class ReceiptLineRoleTrace {
  ReceiptLineRoleTrace({
    required this.lineId,
    required this.completeness,
    required this.productAnchorId,
    required Map<String, String?> roleElementIds,
    required Map<String, String> rejectedCandidates,
  })  : roleElementIds = Map.unmodifiable(roleElementIds),
        rejectedCandidates = Map.unmodifiable(rejectedCandidates);

  final String lineId;
  final ReceiptLineCompleteness completeness;
  final String? productAnchorId;
  final Map<String, String?> roleElementIds;
  final Map<String, String> rejectedCandidates;
}

class ReceiptUnassignedElementTrace {
  const ReceiptUnassignedElementTrace({
    required this.elementId,
    required this.reasonCode,
  });

  final String elementId;
  final String reasonCode;
}

class ReceiptLineDebugTrace {
  ReceiptLineDebugTrace({
    required this.calibrationPolicy,
    required this.medianPositiveElementHeight,
    required Iterable<String> canonicalElementOrder,
    required Iterable<ReceiptElementSpatialTrace> elementPlacements,
    required Iterable<ReceiptRowConstructionTrace> rowDecisions,
    required Iterable<ReceiptColumnConstructionTrace> columnDecisions,
    required Map<ReceiptLineCompleteness, int> completenessCounts,
    required Iterable<String> productAnchorIds,
    required Iterable<ReceiptLineRoleTrace> lineRoles,
    required Iterable<ReceiptUnassignedElementTrace> unassignedElements,
  })  : canonicalElementOrder = List.unmodifiable(canonicalElementOrder),
        elementPlacements = List.unmodifiable(elementPlacements),
        rowDecisions = List.unmodifiable(rowDecisions),
        columnDecisions = List.unmodifiable(columnDecisions),
        completenessCounts = Map.unmodifiable(completenessCounts),
        productAnchorIds = List.unmodifiable(productAnchorIds),
        lineRoles = List.unmodifiable(lineRoles),
        unassignedElements = List.unmodifiable(unassignedElements);

  final ReceiptCalibrationPolicy calibrationPolicy;
  final double? medianPositiveElementHeight;
  final List<String> canonicalElementOrder;
  final List<ReceiptElementSpatialTrace> elementPlacements;
  final List<ReceiptRowConstructionTrace> rowDecisions;
  final List<ReceiptColumnConstructionTrace> columnDecisions;
  final Map<ReceiptLineCompleteness, int> completenessCounts;
  final List<String> productAnchorIds;
  final List<ReceiptLineRoleTrace> lineRoles;
  final List<ReceiptUnassignedElementTrace> unassignedElements;
}
