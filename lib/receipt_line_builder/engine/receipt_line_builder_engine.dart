import '../../receipt_understanding/domain/receipt_element.dart';
import '../../receipt_understanding/domain/receipt_element_type.dart';
import '../domain/receipt_calibration_policy.dart';
import '../domain/receipt_line.dart';
import '../domain/receipt_line_completeness.dart';
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
      );
    }

    final geometries = <ReceiptLineGeometry>[];
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
      );
    }

    final lines = <ReceiptLine>[];
    for (final row
        in _spatialIndex.organize(geometries, medianHeight, _policy)) {
      for (final column in row.columns) {
        lines.addAll(_buildColumn(
          row: row,
          column: column,
          medianHeight: medianHeight,
        ));
      }
    }
    return ReceiptLineResult(
      lines: lines,
      unassignedElements: unassigned,
      failures: failures,
    );
  }

  List<ReceiptLine> _buildColumn({
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
      return List.unmodifiable([
        for (final candidate in candidates)
          _orphan(candidate, row.index, column.index),
      ]);
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
        final draft = _nearestAnchor(candidate, anchors, medianHeight);
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

    return List.unmodifiable([
      for (final draft in anchors)
        draft.toLine(_idGenerator, row.index, column.index),
      for (final candidate in candidates)
        if (unclaimed.containsKey(candidate.element.id))
          _orphan(candidate, row.index, column.index),
    ]);
  }

  _LineDraft _nearestAnchor(
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
    return selected;
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
      return candidate;
    }
    if (existing != null) {
      _rejected[existing.element.id] = 'replaced-by-nearer-spatial-candidate';
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
    return existing;
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
}
