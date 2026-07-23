import '../../receipt_line_builder/domain/receipt_line.dart';
import '../../receipt_line_builder/domain/receipt_line_completeness.dart';
import '../../receipt_line_builder/domain/receipt_line_debug_trace.dart';
import '../../receipt_line_builder/domain/receipt_line_result.dart';
import '../../receipt_understanding/domain/receipt_element.dart';
import '../../receipt_understanding/domain/receipt_element_type.dart';
import '../domain/orphan_line_diagnostic.dart';

class OrphanLineDiagnosticsService {
  const OrphanLineDiagnosticsService();

  Future<List<OrphanLineDiagnostic>> diagnose({
    required List<ReceiptElement> elements,
    required ReceiptLineResult lineResult,
  }) async {
    final elementsById = {
      for (final element in elements) element.id: element,
    };
    final trace = lineResult.debugTrace;
    final placements = <String, ReceiptElementSpatialTrace>{
      for (final placement
          in trace?.elementPlacements ?? const <ReceiptElementSpatialTrace>[])
        placement.elementId: placement,
    };
    final medianHeight =
        trace?.medianPositiveElementHeight ?? _medianHeight(elements);
    final productElements = elements
        .where((element) => element.type == ReceiptElementType.productName)
        .toList(growable: false);
    final comparableProducts =
        productElements.where(_hasValidGeometry).toList(growable: false);

    return List.unmodifiable([
      for (final line in lineResult.lines)
        if (line.completeness == ReceiptLineCompleteness.orphan)
          _diagnose(
            line: line,
            elementsById: elementsById,
            productElementExists: productElements.isNotEmpty,
            comparableProducts: comparableProducts,
            placements: placements,
            medianHeight: medianHeight,
            trace: trace,
          ),
    ]);
  }

  OrphanLineDiagnostic _diagnose({
    required ReceiptLine line,
    required Map<String, ReceiptElement> elementsById,
    required bool productElementExists,
    required List<ReceiptElement> comparableProducts,
    required Map<String, ReceiptElementSpatialTrace> placements,
    required double? medianHeight,
    required ReceiptLineDebugTrace? trace,
  }) {
    final sourceElements = line.referencedElementIds
        .map((id) => elementsById[id])
        .whereType<ReceiptElement>()
        .toList(growable: false);
    final source = sourceElements.isEmpty ? null : sourceElements.first;
    final lineProduct = line.productElementId == null
        ? null
        : elementsById[line.productElementId];
    final candidate = lineProduct?.type == ReceiptElementType.productName
        ? lineProduct
        : source == null || medianHeight == null
            ? null
            : _nearestProduct(source, comparableProducts, medianHeight);
    final sourcePlacement = source == null ? null : placements[source.id];
    final candidatePlacement =
        candidate == null ? null : placements[candidate.id];
    final sameRow = sourcePlacement?.rowIndex == null ||
            candidatePlacement?.rowIndex == null
        ? null
        : sourcePlacement!.rowIndex == candidatePlacement!.rowIndex;
    final sameColumn = sourcePlacement?.columnIndex == null ||
            candidatePlacement?.columnIndex == null
        ? null
        : sameRow == true &&
            sourcePlacement!.columnIndex == candidatePlacement!.columnIndex;
    final horizontalGap = _horizontalGap(source, candidate, medianHeight);
    final verticalDistance = _verticalDistance(source, candidate, medianHeight);
    final verticalOverlap = _verticalOverlap(source, candidate);
    final rejectedEvaluations = _rejectedEvaluations(trace, source?.id);
    final reason = _reason(
      line: line,
      productElementExists: productElementExists,
      candidate: candidate,
      sameRow: sameRow,
      sameColumn: sameColumn,
      horizontalGap: horizontalGap,
      verticalDistance: verticalDistance,
      verticalOverlap: verticalOverlap,
      rejectedEvaluationCount: rejectedEvaluations.length,
      trace: trace,
    );
    final recovery = _recovery(reason);

    return OrphanLineDiagnostic(
      orphanId: line.id,
      sourceElements: [
        for (final element in sourceElements)
          OrphanSourceElement(
            id: element.id,
            text: element.text,
            type: element.type,
          ),
      ],
      productElementExists: productElementExists,
      priceElementExists: line.priceElementId != null &&
          elementsById.containsKey(line.priceElementId),
      quantityElementExists: line.quantityElementId != null &&
          elementsById.containsKey(line.quantityElementId),
      candidateProductElementId: candidate?.id,
      sameRow: sameRow,
      sameColumn: sameColumn,
      horizontalGap: horizontalGap,
      verticalDistance: verticalDistance,
      verticalOverlap: verticalOverlap,
      rejectionReason: reason,
      recoveryPossibility: recovery.$1,
      recoveryReason: recovery.$2,
      groupingAttemptSummary: _groupingSummary(
        candidateId: candidate?.id,
        sameRow: sameRow,
        sameColumn: sameColumn,
        rejectedEvaluationCount: rejectedEvaluations.length,
      ),
    );
  }

  ReceiptElement? _nearestProduct(
    ReceiptElement source,
    List<ReceiptElement> products,
    double medianHeight,
  ) {
    ReceiptElement? selected;
    var selectedScore = double.infinity;
    for (final product in products) {
      if (product.id == source.id) continue;
      final score = _verticalDistance(source, product, medianHeight)! +
          _horizontalGap(source, product, medianHeight)!;
      if (score < selectedScore ||
          (score == selectedScore &&
              (selected == null || product.id.compareTo(selected.id) < 0))) {
        selected = product;
        selectedScore = score;
      }
    }
    return selected;
  }

  OrphanLineReason _reason({
    required ReceiptLine line,
    required bool productElementExists,
    required ReceiptElement? candidate,
    required bool? sameRow,
    required bool? sameColumn,
    required double? horizontalGap,
    required double? verticalDistance,
    required double? verticalOverlap,
    required int rejectedEvaluationCount,
    required ReceiptLineDebugTrace? trace,
  }) {
    if (line.productElementId != null &&
        line.priceElementId == null &&
        line.lineTotalElementId == null) {
      return OrphanLineReason.noPriceElement;
    }
    if (candidate == null) {
      return productElementExists
          ? OrphanLineReason.unknown
          : OrphanLineReason.noProductElement;
    }
    if (rejectedEvaluationCount > 0) {
      return OrphanLineReason.multipleCompetingCandidates;
    }
    if (sameRow == null ||
        sameColumn == null ||
        horizontalGap == null ||
        verticalDistance == null ||
        verticalOverlap == null ||
        trace == null) {
      return OrphanLineReason.unknown;
    }
    final policy = trace.calibrationPolicy;
    if (!sameRow) {
      if (verticalDistance <= policy.rowVerticalDistanceTolerance &&
          verticalOverlap < policy.rowMinimumOverlapRatio) {
        return OrphanLineReason.overlapTooSmall;
      }
      return OrphanLineReason.failedRowGrouping;
    }
    if (!sameColumn) {
      if (horizontalGap > policy.columnGapTolerance) {
        return OrphanLineReason.distanceTooLarge;
      }
      return OrphanLineReason.failedColumnGrouping;
    }
    if (horizontalGap > policy.columnGapTolerance) {
      return OrphanLineReason.distanceTooLarge;
    }
    if (verticalOverlap < policy.rowMinimumOverlapRatio &&
        verticalDistance > policy.rowVerticalDistanceTolerance) {
      return OrphanLineReason.overlapTooSmall;
    }
    return OrphanLineReason.unknown;
  }

  (OrphanRecoveryPossibility, String) _recovery(OrphanLineReason reason) =>
      switch (reason) {
        OrphanLineReason.multipleCompetingCandidates => (
            OrphanRecoveryPossibility.yes,
            'A compatible product anchor was evaluated, but this role lost a deterministic candidate competition.',
          ),
        OrphanLineReason.noPriceElement => (
            OrphanRecoveryPossibility.maybe,
            'A product element exists, but no price evidence is attached.',
          ),
        OrphanLineReason.failedRowGrouping => (
            OrphanRecoveryPossibility.maybe,
            'A product candidate exists in another engine-produced row.',
          ),
        OrphanLineReason.failedColumnGrouping => (
            OrphanRecoveryPossibility.maybe,
            'A product candidate exists in another engine-produced column.',
          ),
        OrphanLineReason.distanceTooLarge => (
            OrphanRecoveryPossibility.maybe,
            'A product candidate exists, but the normalized horizontal distance exceeds the current policy.',
          ),
        OrphanLineReason.overlapTooSmall => (
            OrphanRecoveryPossibility.maybe,
            'A product candidate exists, but vertical overlap evidence is insufficient.',
          ),
        OrphanLineReason.noProductElement => (
            OrphanRecoveryPossibility.no,
            'No product element with valid geometry exists for diagnostic comparison.',
          ),
        OrphanLineReason.unknown => (
            OrphanRecoveryPossibility.no,
            'Existing trace evidence is insufficient to identify a safe recovery path.',
          ),
      };

  List<ReceiptCandidateDecisionTrace> _rejectedEvaluations(
    ReceiptLineDebugTrace? trace,
    String? sourceElementId,
  ) {
    if (trace == null || sourceElementId == null) return const [];
    return [
      for (final anchor in trace.decisionTraces)
        for (final evaluation in anchor.candidateEvaluations)
          if (evaluation.candidateElementId == sourceElementId &&
              !evaluation.accepted)
            evaluation,
    ];
  }

  String _groupingSummary({
    required String? candidateId,
    required bool? sameRow,
    required bool? sameColumn,
    required int rejectedEvaluationCount,
  }) =>
      candidateId == null
          ? 'No product candidate was available for a grouping comparison.'
          : 'Compared with $candidateId: sameRow=${sameRow ?? 'unknown'}, '
              'sameColumn=${sameColumn ?? 'unknown'}, '
              'rejectedEvaluations=$rejectedEvaluationCount.';

  bool _hasValidGeometry(ReceiptElement element) {
    final box = element.boundingBox;
    return box != null &&
        box.x.isFinite &&
        box.y.isFinite &&
        box.width.isFinite &&
        box.height.isFinite &&
        box.width > 0 &&
        box.height > 0;
  }

  double? _medianHeight(List<ReceiptElement> elements) {
    final heights = elements
        .where(_hasValidGeometry)
        .map((element) => element.boundingBox!.height)
        .toList()
      ..sort();
    if (heights.isEmpty) return null;
    final middle = heights.length ~/ 2;
    return heights.length.isOdd
        ? heights[middle]
        : (heights[middle - 1] + heights[middle]) / 2;
  }

  double? _horizontalGap(
    ReceiptElement? left,
    ReceiptElement? right,
    double? medianHeight,
  ) {
    if (left == null ||
        right == null ||
        medianHeight == null ||
        !_hasValidGeometry(left) ||
        !_hasValidGeometry(right)) {
      return null;
    }
    final first = left.boundingBox!;
    final second = right.boundingBox!;
    final firstCenter = first.x + first.width / 2;
    final secondCenter = second.x + second.width / 2;
    final gap = firstCenter <= secondCenter
        ? (second.x - (first.x + first.width)).clamp(0, double.infinity)
        : (first.x - (second.x + second.width)).clamp(0, double.infinity);
    return gap / medianHeight;
  }

  double? _verticalDistance(
    ReceiptElement? first,
    ReceiptElement? second,
    double? medianHeight,
  ) {
    if (first == null ||
        second == null ||
        medianHeight == null ||
        !_hasValidGeometry(first) ||
        !_hasValidGeometry(second)) {
      return null;
    }
    final firstBox = first.boundingBox!;
    final secondBox = second.boundingBox!;
    final firstCenter = firstBox.y + firstBox.height / 2;
    final secondCenter = secondBox.y + secondBox.height / 2;
    return (firstCenter - secondCenter).abs() / medianHeight;
  }

  double? _verticalOverlap(
    ReceiptElement? first,
    ReceiptElement? second,
  ) {
    if (first == null ||
        second == null ||
        !_hasValidGeometry(first) ||
        !_hasValidGeometry(second)) {
      return null;
    }
    final firstBox = first.boundingBox!;
    final secondBox = second.boundingBox!;
    final overlap =
        (firstBox.y + firstBox.height < secondBox.y + secondBox.height
                ? firstBox.y + firstBox.height
                : secondBox.y + secondBox.height) -
            (firstBox.y > secondBox.y ? firstBox.y : secondBox.y);
    if (overlap <= 0) return 0;
    final shortest =
        firstBox.height < secondBox.height ? firstBox.height : secondBox.height;
    return overlap / shortest;
  }
}
