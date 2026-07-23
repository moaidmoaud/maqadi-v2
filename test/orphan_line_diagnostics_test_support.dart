import 'package:maqadi_v2/orphan_line_diagnostics/domain/orphan_line_diagnostic.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_calibration_policy.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_debug_trace.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';

ReceiptLineResult orphanResult({
  required ReceiptLine line,
  ReceiptLineDebugTrace? trace,
}) =>
    ReceiptLineResult(
      lines: [line],
      unassignedElements: const [],
      failures: const [],
      debugTrace: trace,
    );

ReceiptLineDebugTrace orphanTrace({
  required String sourceId,
  required String productId,
  required int sourceRow,
  required int sourceColumn,
  required int productRow,
  required int productColumn,
}) =>
    ReceiptLineDebugTrace(
      calibrationPolicy: const ReceiptCalibrationPolicy(),
      medianPositiveElementHeight: 10,
      canonicalElementOrder: [productId, sourceId],
      elementPlacements: [
        ReceiptElementSpatialTrace(
          elementId: productId,
          status: ReceiptElementSpatialStatus.placed,
          canonicalIndex: 0,
          rowIndex: productRow,
          columnIndex: productColumn,
        ),
        ReceiptElementSpatialTrace(
          elementId: sourceId,
          status: ReceiptElementSpatialStatus.placed,
          canonicalIndex: 1,
          rowIndex: sourceRow,
          columnIndex: sourceColumn,
        ),
      ],
      rowDecisions: const [],
      columnDecisions: const [],
      completenessCounts: const {
        ReceiptLineCompleteness.complete: 0,
        ReceiptLineCompleteness.partial: 0,
        ReceiptLineCompleteness.orphan: 1,
      },
      productAnchorIds: [productId],
      lineRoles: const [],
      unassignedElements: const [],
    );

OrphanLineDiagnostic orphanDiagnostic({
  required String id,
  required OrphanRecoveryPossibility recovery,
}) =>
    OrphanLineDiagnostic(
      orphanId: id,
      sourceElements: const [],
      productElementExists: recovery != OrphanRecoveryPossibility.no,
      priceElementExists: true,
      quantityElementExists: false,
      candidateProductElementId:
          recovery == OrphanRecoveryPossibility.no ? null : 'product',
      sameRow: recovery == OrphanRecoveryPossibility.yes,
      sameColumn: recovery == OrphanRecoveryPossibility.yes,
      horizontalGap: recovery == OrphanRecoveryPossibility.no ? null : 1,
      verticalDistance: recovery == OrphanRecoveryPossibility.no ? null : 0,
      verticalOverlap: recovery == OrphanRecoveryPossibility.no ? null : 1,
      rejectionReason: switch (recovery) {
        OrphanRecoveryPossibility.yes =>
          OrphanLineReason.multipleCompetingCandidates,
        OrphanRecoveryPossibility.maybe => OrphanLineReason.distanceTooLarge,
        OrphanRecoveryPossibility.no => OrphanLineReason.noProductElement,
      },
      recoveryPossibility: recovery,
      recoveryReason: 'test recovery',
      groupingAttemptSummary: 'test grouping',
    );
