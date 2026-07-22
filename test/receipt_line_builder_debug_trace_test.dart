import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_calibration_policy.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_debug_trace.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_geometry.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_spatial_index.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  const engine = ReceiptLineBuilderEngine();

  test('trace exposes policy, median, canonical order, and placements', () {
    final result = engine.build(productRow(quantity: true));
    final trace = result.debugTrace!;

    expect(trace.calibrationPolicy.rowVerticalDistanceTolerance, 0.75);
    expect(trace.calibrationPolicy.rowMinimumOverlapRatio, 0.3);
    expect(trace.calibrationPolicy.columnGapTolerance, 8.0);
    expect(trace.medianPositiveElementHeight, 10);
    expect(trace.canonicalElementOrder, ['a-product', 'a-quantity', 'a-price']);
    expect(
      trace.elementPlacements
          .map((value) =>
              '${value.elementId}:${value.canonicalIndex}:${value.rowIndex}:${value.columnIndex}')
          .toList(),
      ['a-product:0:0:0', 'a-quantity:1:0:0', 'a-price:2:0:0'],
    );
  });

  test('row trace records the exact split inputs and decision', () {
    final trace = engine.build([
      receiptElement('product', ReceiptElementType.productName, y: 0),
      receiptElement('price', ReceiptElementType.price, x: 45, y: 20),
    ]).debugTrace!;

    final decision = trace.rowDecisions.single;
    expect(decision.previousElementId, 'product');
    expect(decision.currentElementId, 'price');
    expect(decision.normalizedVerticalDistance, 2);
    expect(decision.verticalOverlapRatio, 0);
    expect(decision.split, isTrue);
    expect(decision.resultingRowIndex, 1);
  });

  test('column trace records normalized gaps and exact split decision', () {
    final result = engine.build([
      receiptElement('product', ReceiptElementType.productName, x: 0),
      receiptElement('price', ReceiptElementType.price, x: 150),
    ]);
    final decision = result.debugTrace!.columnDecisions.single;

    expect(decision.previousElementId, 'product');
    expect(decision.currentElementId, 'price');
    expect(decision.normalizedHorizontalGap, 11);
    expect(decision.split, isTrue);
    expect(decision.rowIndex, 0);
    expect(decision.resultingColumnIndex, 1);
    expect(result.lines.map((line) => line.completeness),
        [ReceiptLineCompleteness.partial, ReceiptLineCompleteness.orphan]);
  });

  test('trace summarizes anchors, roles, rejection, and completeness', () {
    final trace = engine.build([
      receiptElement('product', ReceiptElementType.productName, width: 40),
      receiptElement('near', ReceiptElementType.price, x: 45),
      receiptElement('far', ReceiptElementType.price, x: 70),
      receiptElement('partial', ReceiptElementType.productName, y: 30),
    ]).debugTrace!;

    expect(trace.completenessCounts, {
      ReceiptLineCompleteness.complete: 1,
      ReceiptLineCompleteness.partial: 1,
      ReceiptLineCompleteness.orphan: 1,
    });
    expect(trace.productAnchorIds, containsAll(['product', 'partial']));
    final complete = trace.lineRoles.singleWhere(
      (value) => value.completeness == ReceiptLineCompleteness.complete,
    );
    expect(complete.productAnchorId, 'product');
    expect(complete.roleElementIds['price'], 'near');
    expect(complete.rejectedCandidates['far'], 'farther-from-product-anchor');
  });

  test('missing geometry is represented without a row or column', () {
    final trace = engine.build([
      receiptElement(
        'missing',
        ReceiptElementType.productName,
        withoutGeometry: true,
      ),
    ]).debugTrace!;

    final placement = trace.elementPlacements.single;
    expect(placement.status, ReceiptElementSpatialStatus.geometryUnavailable);
    expect(placement.canonicalIndex, isNull);
    expect(placement.rowIndex, isNull);
    expect(placement.columnIndex, isNull);
    expect(trace.unassignedElements.single.elementId, 'missing');
    expect(trace.unassignedElements.single.reasonCode, 'geometryUnavailable');
  });

  test('repeated trace generation is deterministic', () {
    final input = [...productRow(), ...productRow(prefix: 'b', y: 30)];
    final first = _signature(engine.build(input).debugTrace!);
    final second = _signature(engine.build(input).debugTrace!);
    expect(first, second);
  });

  test('traced and untraced spatial organization produce identical rows', () {
    final elements = [...productRow(), ...productRow(prefix: 'b', y: 30)];
    final geometries = [
      for (var index = 0; index < elements.length; index++)
        ReceiptLineGeometry.fromElement(elements[index], index),
    ];
    final median = ReceiptLineGeometry.medianPositiveHeight(geometries)!;
    const index = ReceiptLineSpatialIndex();
    final untraced = index.organize(geometries, median);
    final traced = index
        .organizeWithTrace(
          geometries,
          median,
          const ReceiptCalibrationPolicy(),
        )
        .rows;

    expect(_rows(traced), _rows(untraced));
  });

  test('trace collections are immutable', () {
    final trace = engine.build(productRow()).debugTrace!;
    expect(
        () => trace.canonicalElementOrder.add('other'), throwsUnsupportedError);
    expect(() => trace.elementPlacements.clear(), throwsUnsupportedError);
    expect(() => trace.completenessCounts.clear(), throwsUnsupportedError);
    expect(() => trace.lineRoles.single.roleElementIds.clear(),
        throwsUnsupportedError);
  });

  test('accepted candidate trace exposes the passing metrics', () {
    final trace = engine.build([
      receiptElement('product', ReceiptElementType.productName, width: 40),
      receiptElement('price', ReceiptElementType.price, x: 45),
    ]).debugTrace!;

    final anchor = trace.decisionTraces.single;
    final candidate = anchor.candidateEvaluations.single;
    expect(anchor.anchorElementId, 'product');
    expect(candidate.candidateElementId, 'price');
    expect(candidate.candidateType, ReceiptLineCandidateType.price);
    expect(candidate.evaluationOrder, 0);
    expect(candidate.accepted, isTrue);
    expect(candidate.decisionReason, ReceiptCandidateDecisionReason.accepted);
    expect(candidate.sameRow, isTrue);
    expect(candidate.sameColumn, isTrue);
    expect(candidate.rowIndex, 0);
    expect(candidate.columnIndex, 0);
    expect(candidate.horizontalGap, 0.5);
    expect(candidate.verticalDistance, 0);
    expect(candidate.verticalOverlap, 1);
    expect(candidate.spatialScore, -0.5);
  });

  test('rejected candidate trace exposes the failing decision', () {
    final trace = engine.build([
      receiptElement('product', ReceiptElementType.productName, width: 40),
      receiptElement('near', ReceiptElementType.price, x: 45),
      receiptElement('far', ReceiptElementType.price, x: 70),
    ]).debugTrace!;

    final evaluations = trace.decisionTraces.single.candidateEvaluations;
    expect(evaluations.map((value) => value.evaluationOrder), [0, 1]);
    expect(evaluations.first.accepted, isTrue);
    expect(evaluations.last.accepted, isFalse);
    expect(
      evaluations.last.decisionReason,
      ReceiptCandidateDecisionReason.fartherFromProductAnchor,
    );
    expect(evaluations.last.horizontalGap, 3);
    expect(evaluations.last.spatialScore, 2);
  });

  test('trace records alternate-anchor and replacement decisions', () {
    final alternate = engine.build([
      receiptElement('left-product', ReceiptElementType.productName, width: 40),
      receiptElement('price', ReceiptElementType.price, x: 45),
      receiptElement(
        'right-product',
        ReceiptElementType.productName,
        x: 100,
        width: 40,
      ),
    ]).debugTrace!;
    final rightAnchor = alternate.decisionTraces.singleWhere(
      (value) => value.anchorElementId == 'right-product',
    );
    expect(
      rightAnchor.candidateEvaluations.single.decisionReason,
      ReceiptCandidateDecisionReason.nearerAlternateAnchor,
    );

    final replacement = engine.build([
      receiptElement('far', ReceiptElementType.price, x: 0),
      receiptElement(
        'product',
        ReceiptElementType.productName,
        x: 100,
        width: 40,
      ),
      receiptElement('near', ReceiptElementType.price, x: 145),
    ]).debugTrace!;
    final evaluations = replacement.decisionTraces.single.candidateEvaluations;
    expect(
      evaluations.first.decisionReason,
      ReceiptCandidateDecisionReason.replacedByNearerSpatialCandidate,
    );
    expect(evaluations.first.accepted, isFalse);
    expect(evaluations.last.decisionReason,
        ReceiptCandidateDecisionReason.accepted);
    expect(evaluations.last.accepted, isTrue);
  });

  test('decision reasons are strongly typed and stable', () {
    expect(
      ReceiptCandidateDecisionReason.values.map((value) => value.name),
      [
        'accepted',
        'nearerAlternateAnchor',
        'fartherFromProductAnchor',
        'replacedByNearerSpatialCandidate',
      ],
    );
  });

  test('anchor decision trace serializes and restores all evidence', () {
    final original = engine
        .build([
          receiptElement('product', ReceiptElementType.productName, width: 40),
          receiptElement('price', ReceiptElementType.price, x: 45),
        ])
        .debugTrace!
        .decisionTraces
        .single;

    final json = original.toJson();
    final restored = ReceiptAnchorDecisionTrace.fromJson(json);

    expect(restored.toJson(), json);
    expect(restored.lineId, original.lineId);
    expect(restored.anchorElementId, original.anchorElementId);
    expect(
      restored.candidateEvaluations.single.decisionReason,
      ReceiptCandidateDecisionReason.accepted,
    );
  });
}

List<List<List<String>>> _rows(List<ReceiptSpatialRow> rows) => [
      for (final row in rows)
        [
          for (final column in row.columns)
            column.elements.map((value) => value.element.id).toList(),
        ],
    ];

List<Object?> _signature(ReceiptLineDebugTrace trace) => [
      trace.medianPositiveElementHeight,
      trace.canonicalElementOrder,
      for (final value in trace.elementPlacements)
        [
          value.elementId,
          value.status,
          value.canonicalIndex,
          value.rowIndex,
          value.columnIndex,
        ],
      for (final value in trace.rowDecisions)
        [
          value.previousElementId,
          value.currentElementId,
          value.normalizedVerticalDistance,
          value.verticalOverlapRatio,
          value.split,
          value.resultingRowIndex,
        ],
      for (final value in trace.columnDecisions)
        [
          value.rowIndex,
          value.previousElementId,
          value.currentElementId,
          value.normalizedHorizontalGap,
          value.split,
          value.resultingColumnIndex,
        ],
      for (final anchor in trace.decisionTraces)
        [
          anchor.lineId,
          anchor.anchorElementId,
          for (final candidate in anchor.candidateEvaluations)
            [
              candidate.candidateElementId,
              candidate.candidateType,
              candidate.evaluationOrder,
              candidate.accepted,
              candidate.decisionReason,
              candidate.sameRow,
              candidate.sameColumn,
              candidate.rowIndex,
              candidate.columnIndex,
              candidate.horizontalGap,
              candidate.verticalDistance,
              candidate.verticalOverlap,
              candidate.spatialScore,
            ],
        ],
    ];
