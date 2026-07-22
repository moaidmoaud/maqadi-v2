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

enum ReceiptCandidateDecisionReason {
  accepted,
  nearerAlternateAnchor,
  fartherFromProductAnchor,
  replacedByNearerSpatialCandidate,
}

enum ReceiptLineCandidateType {
  productName,
  price,
  quantity,
  discount,
  tax,
  lineTotal,
  unsupported,
}

class ReceiptCandidateDecisionTrace {
  const ReceiptCandidateDecisionTrace({
    required this.candidateElementId,
    required this.candidateType,
    required this.evaluationOrder,
    required this.accepted,
    required this.decisionReason,
    required this.sameRow,
    required this.sameColumn,
    required this.rowIndex,
    required this.columnIndex,
    required this.horizontalGap,
    required this.verticalDistance,
    required this.verticalOverlap,
    required this.spatialScore,
  });

  factory ReceiptCandidateDecisionTrace.fromJson(
    Map<String, Object?> json,
  ) =>
      ReceiptCandidateDecisionTrace(
        candidateElementId: json['candidateElementId']! as String,
        candidateType: ReceiptLineCandidateType.values.byName(
          json['candidateType']! as String,
        ),
        evaluationOrder: json['evaluationOrder']! as int,
        accepted: json['accepted']! as bool,
        decisionReason: ReceiptCandidateDecisionReason.values.byName(
          json['decisionReason']! as String,
        ),
        sameRow: json['sameRow']! as bool,
        sameColumn: json['sameColumn']! as bool,
        rowIndex: json['rowIndex']! as int,
        columnIndex: json['columnIndex']! as int,
        horizontalGap: (json['horizontalGap']! as num).toDouble(),
        verticalDistance: (json['verticalDistance']! as num).toDouble(),
        verticalOverlap: (json['verticalOverlap']! as num).toDouble(),
        spatialScore: (json['spatialScore']! as num).toDouble(),
      );

  final String candidateElementId;
  final ReceiptLineCandidateType candidateType;
  final int evaluationOrder;
  final bool accepted;
  final ReceiptCandidateDecisionReason decisionReason;
  final bool sameRow;
  final bool sameColumn;
  final int rowIndex;
  final int columnIndex;
  final double horizontalGap;
  final double verticalDistance;
  final double verticalOverlap;
  final double spatialScore;

  Map<String, Object> toJson() => {
        'candidateElementId': candidateElementId,
        'candidateType': candidateType.name,
        'evaluationOrder': evaluationOrder,
        'accepted': accepted,
        'decisionReason': decisionReason.name,
        'sameRow': sameRow,
        'sameColumn': sameColumn,
        'rowIndex': rowIndex,
        'columnIndex': columnIndex,
        'horizontalGap': horizontalGap,
        'verticalDistance': verticalDistance,
        'verticalOverlap': verticalOverlap,
        'spatialScore': spatialScore,
      };
}

class ReceiptAnchorDecisionTrace {
  ReceiptAnchorDecisionTrace({
    required this.lineId,
    required this.anchorElementId,
    required Iterable<ReceiptCandidateDecisionTrace> candidateEvaluations,
  }) : candidateEvaluations = List.unmodifiable(candidateEvaluations);

  factory ReceiptAnchorDecisionTrace.fromJson(Map<String, Object?> json) =>
      ReceiptAnchorDecisionTrace(
        lineId: json['lineId']! as String,
        anchorElementId: json['anchorElementId']! as String,
        candidateEvaluations:
            (json['candidateEvaluations']! as List<Object?>).map(
          (value) => ReceiptCandidateDecisionTrace.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );

  final String lineId;
  final String anchorElementId;
  final List<ReceiptCandidateDecisionTrace> candidateEvaluations;

  Map<String, Object> toJson() => {
        'lineId': lineId,
        'anchorElementId': anchorElementId,
        'candidateEvaluations': [
          for (final value in candidateEvaluations) value.toJson(),
        ],
      };
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
    Iterable<ReceiptAnchorDecisionTrace> decisionTraces = const [],
  })  : canonicalElementOrder = List.unmodifiable(canonicalElementOrder),
        elementPlacements = List.unmodifiable(elementPlacements),
        rowDecisions = List.unmodifiable(rowDecisions),
        columnDecisions = List.unmodifiable(columnDecisions),
        completenessCounts = Map.unmodifiable(completenessCounts),
        productAnchorIds = List.unmodifiable(productAnchorIds),
        lineRoles = List.unmodifiable(lineRoles),
        unassignedElements = List.unmodifiable(unassignedElements),
        decisionTraces = List.unmodifiable(decisionTraces);

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
  final List<ReceiptAnchorDecisionTrace> decisionTraces;
}
