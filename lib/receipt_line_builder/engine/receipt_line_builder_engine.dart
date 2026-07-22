import '../../receipt_understanding/domain/receipt_element.dart';
import '../../receipt_understanding/domain/receipt_element_type.dart';
import '../domain/receipt_calibration_policy.dart';
import '../domain/receipt_line.dart';
import '../domain/receipt_line_completeness.dart';
import '../domain/receipt_line_debug_trace.dart';
import '../domain/receipt_line_evidence.dart';
import '../domain/receipt_line_failure.dart';
import '../domain/receipt_line_result.dart';
import '../domain/unassigned_receipt_element.dart';
import 'receipt_line_geometry.dart';
import 'receipt_line_grouping_rules.dart';
import 'receipt_line_id_generator.dart';
import 'receipt_line_spatial_index.dart';

class ReceiptLineBuilderEngine {
  const ReceiptLineBuilderEngine({
    ReceiptCalibrationPolicy policy = const ReceiptCalibrationPolicy(),
    ReceiptLineGroupingRules rules = const ReceiptLineGroupingRules(),
    ReceiptLineSpatialIndex spatialIndex = const ReceiptLineSpatialIndex(),
    ReceiptLineIdGenerator idGenerator = const ReceiptLineIdGenerator(),
  })  : _policy = policy,
        _rules = rules,
        _spatialIndex = spatialIndex,
        _idGenerator = idGenerator;

  final ReceiptCalibrationPolicy _policy;
  final ReceiptLineGroupingRules _rules;
  final ReceiptLineSpatialIndex _spatialIndex;
  final ReceiptLineIdGenerator _idGenerator;

  ReceiptLineResult build(List<ReceiptElement> elements) {
    if (!_policy.isValid) {
      throw const ReceiptLineFailure(
        code: ReceiptLineFailureCode.groupingFailed,
        message: 'Receipt calibration policy contains invalid ratios.',
      );
    }
    if (elements.isEmpty) {
      return ReceiptLineResult(
        lines: const [],
        unassignedElements: const [],
        failures: const [],
        debugTrace: _debugTrace(
          lines: const [],
          unassigned: const [],
          medianHeight: null,
          spatial: null,
          missingGeometryIds: const [],
        ),
      );
    }

    final geometries = <ReceiptLineGeometry>[];
    final missingGeometryIds = <String>[];
    final unassigned = <UnassignedReceiptElement>[];
    final failures = <ReceiptLineFailure>[];
    for (var index = 0; index < elements.length; index++) {
      final element = elements[index];
      if (_rules.isExcluded(element.type) ||
          !_rules.isGroupable(element.type)) {
        unassigned.add(_unassigned(
          element.id,
          UnassignedReceiptElementReason.excludedElementType,
          'excluded-element-type',
          'This structural element type does not form a receipt line.',
        ));
        continue;
      }
      if (!ReceiptLineGeometry.hasValidRegion(element)) {
        missingGeometryIds.add(element.id);
        if (element.boundingBox != null) {
          failures.add(ReceiptLineFailure(
            code: ReceiptLineFailureCode.invalidGeometry,
            message: 'Element geometry is invalid.',
            elementId: element.id,
          ));
        }
        unassigned.add(_unassigned(
          element.id,
          UnassignedReceiptElementReason.geometryUnavailable,
          'geometryUnavailable',
          'Geometry is unavailable, so the element was not spatially grouped.',
        ));
        continue;
      }
      geometries.add(ReceiptLineGeometry.fromElement(element, index));
    }

    final medianHeight = ReceiptLineGeometry.medianPositiveHeight(geometries);
    if (medianHeight == null) {
      return ReceiptLineResult(
        lines: const [],
        unassignedElements: unassigned,
        failures: failures,
        debugTrace: _debugTrace(
          lines: const [],
          unassigned: unassigned,
          medianHeight: null,
          spatial: null,
          missingGeometryIds: missingGeometryIds,
        ),
      );
    }

    final spatial =
        _spatialIndex.organizeWithTrace(geometries, medianHeight, _policy);
    final lines = <ReceiptLine>[];
    final decisionTraces = <ReceiptAnchorDecisionTrace>[];
    for (final row in spatial.rows) {
      for (final column in row.columns) {
        final columnResult = _buildColumn(
          row: row,
          column: column,
          medianHeight: medianHeight,
        );
        lines.addAll(columnResult.lines);
        decisionTraces.addAll(columnResult.decisionTraces);
      }
    }
    return ReceiptLineResult(
      lines: lines,
      unassignedElements: unassigned,
      failures: failures,
      debugTrace: _debugTrace(
        lines: lines,
        unassigned: unassigned,
        medianHeight: medianHeight,
        spatial: spatial,
        missingGeometryIds: missingGeometryIds,
        decisionTraces: decisionTraces,
      ),
    );
  }

  ReceiptLineDebugTrace _debugTrace({
    required List<ReceiptLine> lines,
    required List<UnassignedReceiptElement> unassigned,
    required double? medianHeight,
    required ReceiptSpatialIndexResult? spatial,
    required List<String> missingGeometryIds,
    Iterable<ReceiptAnchorDecisionTrace> decisionTraces = const [],
  }) =>
      ReceiptLineDebugTrace(
        calibrationPolicy: _policy,
        medianPositiveElementHeight: medianHeight,
        canonicalElementOrder:
            spatial?.canonicalElementOrder ?? const <String>[],
        elementPlacements: [
          ...?spatial?.elementPlacements,
          for (final id in missingGeometryIds)
            ReceiptElementSpatialTrace(
              elementId: id,
              status: ReceiptElementSpatialStatus.geometryUnavailable,
              canonicalIndex: null,
              rowIndex: null,
              columnIndex: null,
            ),
        ],
        rowDecisions: spatial?.rowDecisions ?? const [],
        columnDecisions: spatial?.columnDecisions ?? const [],
        completenessCounts: {
          for (final value in ReceiptLineCompleteness.values)
            value: lines.where((line) => line.completeness == value).length,
        },
        productAnchorIds:
            lines.map((line) => line.productElementId).whereType<String>(),
        lineRoles: [
          for (final line in lines)
            ReceiptLineRoleTrace(
              lineId: line.id,
              completeness: line.completeness,
              productAnchorId: line.productElementId,
              roleElementIds: {
                'product': line.productElementId,
                'quantity': line.quantityElementId,
                'price': line.priceElementId,
                'lineTotal': line.lineTotalElementId,
                'discount': line.discountElementId,
                'tax': line.taxElementId,
              },
              rejectedCandidates: line.evidence.rejectedCandidates,
            ),
        ],
        unassignedElements: [
          for (final value in unassigned)
            ReceiptUnassignedElementTrace(
              elementId: value.elementId,
              reasonCode: value.reasonCode.name,
            ),
        ],
        decisionTraces: decisionTraces,
      );

  _ColumnBuildResult _buildColumn({
    required ReceiptSpatialRow row,
    required ReceiptSpatialColumn column,
    required double medianHeight,
  }) {
    final anchors = column.elements
        .where((value) => value.element.type == ReceiptElementType.productName)
        .map((value) => _LineDraft(value))
        .toList(growable: false);
    final candidates = column.elements
        .where((value) => value.element.type != ReceiptElementType.productName)
        .toList(growable: false);
    if (anchors.isEmpty) {
      return _ColumnBuildResult(
        lines: [
          for (final candidate in candidates)
            _orphan(candidate, row.index, column.index),
        ],
        decisionTraces: const [],
      );
    }

    final unclaimed = <String, ReceiptLineGeometry>{
      for (final candidate in candidates) candidate.element.id: candidate,
    };
    for (final role in const [
      ReceiptElementType.quantity,
      ReceiptElementType.price,
      ReceiptElementType.total,
      ReceiptElementType.discount,
      ReceiptElementType.tax,
    ]) {
      final roleCandidates = candidates
          .where((candidate) => candidate.element.type == role)
          .toList(growable: false);
      for (final candidate in roleCandidates) {
        final selection = _nearestAnchor(candidate, anchors, medianHeight);
        for (final draft in selection.consideredAnchors) {
          if (!identical(draft, selection.selected)) {
            draft.recordAlternateAnchorCandidate(
              candidate: candidate,
              medianHeight: medianHeight,
              rowIndex: row.index,
              columnIndex: column.index,
            );
          }
        }
        final draft = selection.selected;
        final displaced = draft.attach(
          role: role,
          candidate: candidate,
          medianHeight: medianHeight,
          rowIndex: row.index,
          columnIndex: column.index,
        );
        if (displaced == candidate) continue;
        unclaimed.remove(candidate.element.id);
        if (displaced != null) unclaimed[displaced.element.id] = displaced;
      }
    }

    final lines = <ReceiptLine>[];
    final decisionTraces = <ReceiptAnchorDecisionTrace>[];
    for (final draft in anchors) {
      final line = draft.toLine(_idGenerator, row.index, column.index);
      lines.add(line);
      decisionTraces.add(draft.toDecisionTrace(line.id));
    }
    lines.addAll([
      for (final candidate in candidates)
        if (unclaimed.containsKey(candidate.element.id))
          _orphan(candidate, row.index, column.index),
    ]);
    return _ColumnBuildResult(
      lines: lines,
      decisionTraces: decisionTraces,
    );
  }

  _AnchorSelection _nearestAnchor(
    ReceiptLineGeometry candidate,
    List<_LineDraft> anchors,
    double medianHeight,
  ) {
    var low = 0;
    var high = anchors.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (anchors[middle].anchor.left < candidate.left) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final rightIndex = low.clamp(0, anchors.length - 1);
    final leftIndex = (low - 1).clamp(0, anchors.length - 1);
    final left = anchors[leftIndex];
    final right = anchors[rightIndex];
    final leftDistance = _distance(candidate, left.anchor, medianHeight);
    final rightDistance = _distance(candidate, right.anchor, medianHeight);
    final selected = leftDistance < rightDistance
        ? left
        : rightDistance < leftDistance
            ? right
            : left.anchor.element.id.compareTo(right.anchor.element.id) <= 0
                ? left
                : right;
    return _AnchorSelection(
      selected: selected,
      consideredAnchors: identical(left, right) ? [left] : [left, right],
    );
  }

  double _distance(
    ReceiptLineGeometry candidate,
    ReceiptLineGeometry anchor,
    double medianHeight,
  ) =>
      candidate.normalizedVerticalDistance(anchor, medianHeight) +
      candidate.normalizedHorizontalDistance(anchor, medianHeight);

  ReceiptLine _orphan(
    ReceiptLineGeometry geometry,
    int rowIndex,
    int columnIndex,
  ) {
    final roles = _rolesFor(geometry.element.type, geometry.element.id);
    final evidence = ReceiptLineEvidence(
      anchorElementId: null,
      attachedElementIds: [geometry.element.id],
      normalizedVerticalDistances: const {},
      normalizedHorizontalDistances: const {},
      overlapMetrics: const {},
      columnEvidence: {
        geometry.element.id: 'row:$rowIndex,column:$columnIndex',
      },
      appliedGroupingRule: 'unattached-structural-role',
      rejectedCandidates: const {},
      confidenceFactors: const [
        'bounded-geometry',
        'row-first',
        'column-second',
      ],
      summary: 'No compatible product anchor was spatially available.',
    );
    return ReceiptLine(
      id: _idGenerator.generate(
        completeness: ReceiptLineCompleteness.orphan,
        roles: roles,
      ),
      productElementId: null,
      priceElementId: roles['price'],
      quantityElementId: roles['quantity'],
      discountElementId: roles['discount'],
      taxElementId: roles['tax'],
      lineTotalElementId: roles['lineTotal'],
      completeness: ReceiptLineCompleteness.orphan,
      evidence: evidence,
    );
  }

  Map<String, String?> _rolesFor(ReceiptElementType type, String id) => {
        'product': null,
        'quantity': type == ReceiptElementType.quantity ? id : null,
        'price': type == ReceiptElementType.price ? id : null,
        'lineTotal': type == ReceiptElementType.total ? id : null,
        'discount': type == ReceiptElementType.discount ? id : null,
        'tax': type == ReceiptElementType.tax ? id : null,
      };

  UnassignedReceiptElement _unassigned(
    String elementId,
    UnassignedReceiptElementReason reason,
    String rule,
    String summary,
  ) =>
      UnassignedReceiptElement(
        elementId: elementId,
        reasonCode: reason,
        evidence: ReceiptLineEvidence(
          anchorElementId: null,
          attachedElementIds: [elementId],
          normalizedVerticalDistances: const {},
          normalizedHorizontalDistances: const {},
          overlapMetrics: const {},
          columnEvidence: const {},
          appliedGroupingRule: rule,
          rejectedCandidates: const {},
          confidenceFactors: const [],
          summary: summary,
        ),
      );
}

class _LineDraft {
  _LineDraft(this.anchor);

  final ReceiptLineGeometry anchor;
  final Map<ReceiptElementType, ReceiptLineGeometry> _attached = {};
  final Map<String, double> _verticalDistances = {};
  final Map<String, double> _horizontalDistances = {};
  final Map<String, double> _overlaps = {};
  final Map<String, String> _columns = {};
  final Map<String, String> _rejected = {};
  final List<_CandidateDecisionDraft> _candidateEvaluations = [];
  final Map<String, _CandidateDecisionDraft> _selectedEvaluations = {};
  int _nextEvaluationOrder = 0;

  void recordAlternateAnchorCandidate({
    required ReceiptLineGeometry candidate,
    required double medianHeight,
    required int rowIndex,
    required int columnIndex,
  }) {
    _recordCandidate(
      candidate: candidate,
      medianHeight: medianHeight,
      rowIndex: rowIndex,
      columnIndex: columnIndex,
      accepted: false,
      reason: ReceiptCandidateDecisionReason.nearerAlternateAnchor,
    );
  }

  ReceiptLineGeometry? attach({
    required ReceiptElementType role,
    required ReceiptLineGeometry candidate,
    required double medianHeight,
    required int rowIndex,
    required int columnIndex,
  }) {
    final existing = _attached[role];
    if (existing != null &&
        _score(existing, medianHeight) <= _score(candidate, medianHeight)) {
      _rejected[candidate.element.id] = 'farther-from-product-anchor';
      _recordCandidate(
        candidate: candidate,
        medianHeight: medianHeight,
        rowIndex: rowIndex,
        columnIndex: columnIndex,
        accepted: false,
        reason: ReceiptCandidateDecisionReason.fartherFromProductAnchor,
      );
      return candidate;
    }
    if (existing != null) {
      _rejected[existing.element.id] = 'replaced-by-nearer-spatial-candidate';
      final displacedTrace = _selectedEvaluations[existing.element.id];
      if (displacedTrace != null) {
        displacedTrace
          ..accepted = false
          ..decisionReason =
              ReceiptCandidateDecisionReason.replacedByNearerSpatialCandidate;
      }
      _removeMetrics(existing.element.id);
    }
    _attached[role] = candidate;
    final id = candidate.element.id;
    _verticalDistances[id] =
        candidate.normalizedVerticalDistance(anchor, medianHeight);
    _horizontalDistances[id] =
        candidate.normalizedHorizontalDistance(anchor, medianHeight);
    _overlaps[id] = candidate.verticalOverlap(anchor);
    _columns[id] = 'row:$rowIndex,column:$columnIndex';
    _selectedEvaluations[id] = _recordCandidate(
      candidate: candidate,
      medianHeight: medianHeight,
      rowIndex: rowIndex,
      columnIndex: columnIndex,
      accepted: true,
      reason: ReceiptCandidateDecisionReason.accepted,
    );
    return existing;
  }

  _CandidateDecisionDraft _recordCandidate({
    required ReceiptLineGeometry candidate,
    required double medianHeight,
    required int rowIndex,
    required int columnIndex,
    required bool accepted,
    required ReceiptCandidateDecisionReason reason,
  }) {
    final value = _CandidateDecisionDraft(
      candidate: candidate,
      evaluationOrder: _nextEvaluationOrder++,
      accepted: accepted,
      decisionReason: reason,
      rowIndex: rowIndex,
      columnIndex: columnIndex,
      horizontalGap:
          candidate.normalizedHorizontalDistance(anchor, medianHeight),
      verticalDistance:
          candidate.normalizedVerticalDistance(anchor, medianHeight),
      verticalOverlap: candidate.verticalOverlap(anchor),
      spatialScore: _score(candidate, medianHeight),
    );
    _candidateEvaluations.add(value);
    return value;
  }

  double _score(ReceiptLineGeometry value, double medianHeight) =>
      value.normalizedVerticalDistance(anchor, medianHeight) +
      value.normalizedHorizontalDistance(anchor, medianHeight) -
      value.verticalOverlap(anchor);

  void _removeMetrics(String id) {
    _verticalDistances.remove(id);
    _horizontalDistances.remove(id);
    _overlaps.remove(id);
    _columns.remove(id);
  }

  ReceiptLine toLine(
    ReceiptLineIdGenerator idGenerator,
    int rowIndex,
    int columnIndex,
  ) {
    final productId = anchor.element.id;
    final priceId = _attached[ReceiptElementType.price]?.element.id;
    final completeness = priceId == null
        ? ReceiptLineCompleteness.partial
        : ReceiptLineCompleteness.complete;
    final roles = <String, String?>{
      'product': productId,
      'quantity': _attached[ReceiptElementType.quantity]?.element.id,
      'price': priceId,
      'lineTotal': _attached[ReceiptElementType.total]?.element.id,
      'discount': _attached[ReceiptElementType.discount]?.element.id,
      'tax': _attached[ReceiptElementType.tax]?.element.id,
    };
    final attachedIds = roles.values.whereType<String>().toList();
    return ReceiptLine(
      id: idGenerator.generate(completeness: completeness, roles: roles),
      productElementId: productId,
      priceElementId: priceId,
      quantityElementId: roles['quantity'],
      discountElementId: roles['discount'],
      taxElementId: roles['tax'],
      lineTotalElementId: roles['lineTotal'],
      completeness: completeness,
      evidence: ReceiptLineEvidence(
        anchorElementId: productId,
        attachedElementIds: attachedIds,
        normalizedVerticalDistances: _verticalDistances,
        normalizedHorizontalDistances: _horizontalDistances,
        overlapMetrics: _overlaps,
        columnEvidence: {
          productId: 'row:$rowIndex,column:$columnIndex',
          ..._columns,
        },
        appliedGroupingRule: 'rows-columns-nearest-product-anchor',
        rejectedCandidates: _rejected,
        confidenceFactors: const [
          'same-row',
          'same-column',
          'median-height-normalized',
          'spatial-nearest-anchor',
        ],
        summary: priceId == null
            ? 'Product structure is incomplete because no price was attached.'
            : 'Product and price were grouped by normalized spatial evidence.',
      ),
    );
  }

  ReceiptAnchorDecisionTrace toDecisionTrace(String lineId) =>
      ReceiptAnchorDecisionTrace(
        lineId: lineId,
        anchorElementId: anchor.element.id,
        candidateEvaluations: [
          for (final value in _candidateEvaluations) value.toTrace(),
        ],
      );
}

class _ColumnBuildResult {
  _ColumnBuildResult({
    required Iterable<ReceiptLine> lines,
    required Iterable<ReceiptAnchorDecisionTrace> decisionTraces,
  })  : lines = List.unmodifiable(lines),
        decisionTraces = List.unmodifiable(decisionTraces);

  final List<ReceiptLine> lines;
  final List<ReceiptAnchorDecisionTrace> decisionTraces;
}

class _AnchorSelection {
  const _AnchorSelection({
    required this.selected,
    required this.consideredAnchors,
  });

  final _LineDraft selected;
  final List<_LineDraft> consideredAnchors;
}

class _CandidateDecisionDraft {
  _CandidateDecisionDraft({
    required this.candidate,
    required this.evaluationOrder,
    required this.accepted,
    required this.decisionReason,
    required this.rowIndex,
    required this.columnIndex,
    required this.horizontalGap,
    required this.verticalDistance,
    required this.verticalOverlap,
    required this.spatialScore,
  });

  final ReceiptLineGeometry candidate;
  final int evaluationOrder;
  bool accepted;
  ReceiptCandidateDecisionReason decisionReason;
  final int rowIndex;
  final int columnIndex;
  final double horizontalGap;
  final double verticalDistance;
  final double verticalOverlap;
  final double spatialScore;

  ReceiptCandidateDecisionTrace toTrace() => ReceiptCandidateDecisionTrace(
        candidateElementId: candidate.element.id,
        candidateType: _candidateType(candidate.element.type),
        evaluationOrder: evaluationOrder,
        accepted: accepted,
        decisionReason: decisionReason,
        sameRow: true,
        sameColumn: true,
        rowIndex: rowIndex,
        columnIndex: columnIndex,
        horizontalGap: horizontalGap,
        verticalDistance: verticalDistance,
        verticalOverlap: verticalOverlap,
        spatialScore: spatialScore,
      );

  ReceiptLineCandidateType _candidateType(ReceiptElementType type) =>
      switch (type) {
        ReceiptElementType.productName => ReceiptLineCandidateType.productName,
        ReceiptElementType.price => ReceiptLineCandidateType.price,
        ReceiptElementType.quantity => ReceiptLineCandidateType.quantity,
        ReceiptElementType.discount => ReceiptLineCandidateType.discount,
        ReceiptElementType.tax => ReceiptLineCandidateType.tax,
        ReceiptElementType.total => ReceiptLineCandidateType.lineTotal,
        ReceiptElementType.unknown ||
        ReceiptElementType.storeName ||
        ReceiptElementType.header ||
        ReceiptElementType.metadata ||
        ReceiptElementType.footer =>
          ReceiptLineCandidateType.unsupported,
      };
}
