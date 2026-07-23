import '../../orphan_line_diagnostics/application/orphan_line_diagnostics_service.dart';
import '../../orphan_line_diagnostics/domain/orphan_line_diagnostic.dart';
import '../../receipt_line_builder/domain/receipt_line.dart';
import '../../receipt_line_builder/domain/receipt_line_completeness.dart';
import '../../receipt_line_builder/domain/receipt_line_debug_trace.dart';
import '../../receipt_line_builder/domain/receipt_line_evidence.dart';
import '../../receipt_line_builder/domain/receipt_line_result.dart';
import '../../receipt_understanding/domain/receipt_element.dart';
import '../../receipt_understanding/domain/receipt_element_type.dart';
import '../domain/orphan_line_recovery_result.dart';

class OrphanLineRecoveryService {
  const OrphanLineRecoveryService({
    OrphanLineDiagnosticsService diagnosticsService =
        const OrphanLineDiagnosticsService(),
  }) : _diagnosticsService = diagnosticsService;

  final OrphanLineDiagnosticsService _diagnosticsService;

  Future<OrphanLineRecoveryResult> recover({
    required List<ReceiptElement> elements,
    required ReceiptLineResult lineResult,
    List<OrphanLineDiagnostic>? diagnostics,
  }) async {
    final resolvedDiagnostics = diagnostics ??
        await _diagnosticsService.diagnose(
          elements: elements,
          lineResult: lineResult,
        );
    final diagnosticsById = {
      for (final diagnostic in resolvedDiagnostics)
        diagnostic.orphanId: diagnostic,
    };
    final elementsById = {for (final element in elements) element.id: element};
    final productLinesByElementId = {
      for (final line in lineResult.lines)
        if (line.productElementId != null) line.productElementId!: line,
    };
    final placements = {
      for (final placement in lineResult.debugTrace?.elementPlacements ??
          const <ReceiptElementSpatialTrace>[])
        placement.elementId: placement,
    };
    final proposals = <_RecoveryProposal>[];
    final attemptsByOrphanId = <String, OrphanRecoveryAttempt>{};

    for (final orphan in lineResult.lines.where(
      (line) => line.completeness == ReceiptLineCompleteness.orphan,
    )) {
      final diagnostic = diagnosticsById[orphan.id];
      final sourceId = orphan.referencedElementIds.isEmpty
          ? null
          : orphan.referencedElementIds.first;
      final source = sourceId == null ? null : elementsById[sourceId];
      final candidateLine = diagnostic?.candidateProductElementId == null
          ? null
          : productLinesByElementId[diagnostic!.candidateProductElementId];
      final rejected = _proposalOrFailure(
        orphan: orphan,
        source: source,
        diagnostic: diagnostic,
        candidateLine: candidateLine,
        productLines: productLinesByElementId.values.toList(growable: false),
        placements: placements,
      );
      if (rejected.attempt != null) {
        attemptsByOrphanId[orphan.id] = rejected.attempt!;
      } else {
        proposals.add(rejected.proposal!);
      }
    }

    final proposalGroups = <String, List<_RecoveryProposal>>{};
    for (final proposal in proposals) {
      final key = '${proposal.target.id}:${proposal.role.name}';
      proposalGroups.putIfAbsent(key, () => []).add(proposal);
    }

    final recoveredTargets = <String, ReceiptLine>{};
    final recoveredOrphanIds = <String>{};
    for (final proposal in proposals) {
      final group =
          proposalGroups['${proposal.target.id}:${proposal.role.name}']!;
      if (group.length > 1) {
        attemptsByOrphanId[proposal.orphan.id] = _unrecoverableAttempt(
          proposal.orphan,
          proposal.diagnostic,
          OrphanRecoveryDecisionReason.competingOrphans,
          'Multiple orphan elements compete for the same line role.',
          candidateLine: proposal.target,
          rule: proposal.rule,
        );
        continue;
      }
      final current = recoveredTargets[proposal.target.id] ?? proposal.target;
      if (!_roleIsAvailable(current, proposal.role)) {
        attemptsByOrphanId[proposal.orphan.id] = _unrecoverableAttempt(
          proposal.orphan,
          proposal.diagnostic,
          OrphanRecoveryDecisionReason.roleAlreadyAssigned,
          'The candidate line already contains this structural role.',
          candidateLine: current,
          rule: proposal.rule,
        );
        continue;
      }
      final recovered = _attach(current, proposal);
      recoveredTargets[proposal.target.id] = recovered;
      recoveredOrphanIds.add(proposal.orphan.id);
      attemptsByOrphanId[proposal.orphan.id] = OrphanRecoveryAttempt(
        originalOrphanId: proposal.orphan.id,
        sourceElementIds: proposal.orphan.referencedElementIds,
        candidateLineId: proposal.target.id,
        candidateProductElementId: proposal.target.productElementId,
        sameRow: proposal.diagnostic.sameRow,
        sameColumn: proposal.diagnostic.sameColumn,
        horizontalGap: proposal.diagnostic.horizontalGap,
        verticalDistance: proposal.diagnostic.verticalDistance,
        verticalOverlap: proposal.diagnostic.verticalOverlap,
        rule: proposal.rule,
        confidence: proposal.rule == OrphanRecoveryRule.sameRowNearestProduct
            ? OrphanRecoveryConfidence.high
            : OrphanRecoveryConfidence.moderate,
        outcome: recovered.completeness == ReceiptLineCompleteness.complete
            ? OrphanRecoveryOutcome.recoveredComplete
            : OrphanRecoveryOutcome.recoveredPartial,
        decisionReason:
            proposal.rule == OrphanRecoveryRule.sameRowNearestProduct
                ? OrphanRecoveryDecisionReason.recoveredUniqueSameRow
                : OrphanRecoveryDecisionReason.recoveredUniqueSameColumn,
        recoveredLineId: recovered.id,
        recoveredCompleteness: recovered.completeness,
        summary:
            'The orphan was attached to the uniquely identified product line using ${proposal.rule.name}.',
      );
    }

    return OrphanLineRecoveryResult(
      lines: [
        for (final line in lineResult.lines)
          if (!recoveredOrphanIds.contains(line.id))
            recoveredTargets[line.id] ?? line,
      ],
      attempts: [
        for (final line in lineResult.lines)
          if (line.completeness == ReceiptLineCompleteness.orphan)
            attemptsByOrphanId[line.id]!,
      ],
    );
  }

  _ProposalDecision _proposalOrFailure({
    required ReceiptLine orphan,
    required ReceiptElement? source,
    required OrphanLineDiagnostic? diagnostic,
    required ReceiptLine? candidateLine,
    required List<ReceiptLine> productLines,
    required Map<String, ReceiptElementSpatialTrace> placements,
  }) {
    if (source == null || !_isRecoverableRole(source.type)) {
      return _ProposalDecision.attempt(_unrecoverableAttempt(
        orphan,
        diagnostic,
        OrphanRecoveryDecisionReason.unsupportedOrphanRole,
        'The orphan does not contain one supported structural role.',
      ));
    }
    if (diagnostic == null ||
        diagnostic.candidateProductElementId == null ||
        candidateLine == null) {
      return _ProposalDecision.attempt(_unrecoverableAttempt(
        orphan,
        diagnostic,
        OrphanRecoveryDecisionReason.noProductCandidate,
        'No product line is available for deterministic recovery.',
      ));
    }
    if (diagnostic.sameRow == null || diagnostic.sameColumn == null) {
      return _ProposalDecision.attempt(_unrecoverableAttempt(
        orphan,
        diagnostic,
        OrphanRecoveryDecisionReason.geometryUnavailable,
        'Geometry or spatial placement is unavailable.',
        candidateLine: candidateLine,
      ));
    }
    final rule = diagnostic.sameRow == true
        ? OrphanRecoveryRule.sameRowNearestProduct
        : diagnostic.sameColumn == true
            ? OrphanRecoveryRule.sameColumnNearestProduct
            : OrphanRecoveryRule.none;
    if (rule == OrphanRecoveryRule.none) {
      return _ProposalDecision.attempt(_unrecoverableAttempt(
        orphan,
        diagnostic,
        OrphanRecoveryDecisionReason.spatialRelationshipInsufficient,
        'The nearest product is in neither the same row nor the same column.',
        candidateLine: candidateLine,
      ));
    }
    if (!_roleIsAvailable(candidateLine, source.type)) {
      return _ProposalDecision.attempt(_unrecoverableAttempt(
        orphan,
        diagnostic,
        OrphanRecoveryDecisionReason.roleAlreadyAssigned,
        'The candidate line already contains this structural role.',
        candidateLine: candidateLine,
        rule: rule,
      ));
    }
    final compatibleCandidates = _compatibleCandidateCount(
      sourceId: source.id,
      role: source.type,
      sameRow: diagnostic.sameRow!,
      productLines: productLines,
      placements: placements,
    );
    if (compatibleCandidates > 1) {
      return _ProposalDecision.attempt(_unrecoverableAttempt(
        orphan,
        diagnostic,
        OrphanRecoveryDecisionReason.multipleProductCandidates,
        'Multiple product lines satisfy the same spatial recovery rule.',
        candidateLine: candidateLine,
        rule: rule,
      ));
    }
    return _ProposalDecision.proposal(_RecoveryProposal(
      orphan: orphan,
      source: source,
      target: candidateLine,
      diagnostic: diagnostic,
      role: source.type,
      rule: rule,
    ));
  }

  ReceiptLine _attach(ReceiptLine target, _RecoveryProposal proposal) {
    final sourceId = proposal.source.id;
    final priceId = proposal.role == ReceiptElementType.price
        ? sourceId
        : target.priceElementId;
    final completeness = priceId == null
        ? ReceiptLineCompleteness.partial
        : ReceiptLineCompleteness.complete;
    final attachedIds = [
      ...target.evidence.attachedElementIds,
      if (!target.evidence.attachedElementIds.contains(sourceId)) sourceId,
    ];
    return ReceiptLine(
      id: target.id,
      productElementId: target.productElementId,
      priceElementId: priceId,
      quantityElementId: proposal.role == ReceiptElementType.quantity
          ? sourceId
          : target.quantityElementId,
      discountElementId: proposal.role == ReceiptElementType.discount
          ? sourceId
          : target.discountElementId,
      taxElementId: proposal.role == ReceiptElementType.tax
          ? sourceId
          : target.taxElementId,
      lineTotalElementId: proposal.role == ReceiptElementType.total
          ? sourceId
          : target.lineTotalElementId,
      completeness: completeness,
      evidence: ReceiptLineEvidence(
        anchorElementId: target.productElementId,
        attachedElementIds: attachedIds,
        normalizedVerticalDistances: {
          ...target.evidence.normalizedVerticalDistances,
          if (proposal.diagnostic.verticalDistance != null)
            sourceId: proposal.diagnostic.verticalDistance!,
        },
        normalizedHorizontalDistances: {
          ...target.evidence.normalizedHorizontalDistances,
          if (proposal.diagnostic.horizontalGap != null)
            sourceId: proposal.diagnostic.horizontalGap!,
        },
        overlapMetrics: {
          ...target.evidence.overlapMetrics,
          if (proposal.diagnostic.verticalOverlap != null)
            sourceId: proposal.diagnostic.verticalOverlap!,
        },
        columnEvidence: {
          ...target.evidence.columnEvidence,
          sourceId: proposal.rule.name,
        },
        appliedGroupingRule: 'post-builder-${proposal.rule.name}',
        rejectedCandidates: target.evidence.rejectedCandidates,
        confidenceFactors: [
          ...target.evidence.confidenceFactors,
          proposal.rule.name,
          'diagnostics-driven',
          'unique-nearest-product',
        ],
        summary:
            'The original line was preserved and augmented by the deterministic orphan recovery pass.',
      ),
    );
  }

  OrphanRecoveryAttempt _unrecoverableAttempt(
    ReceiptLine orphan,
    OrphanLineDiagnostic? diagnostic,
    OrphanRecoveryDecisionReason reason,
    String summary, {
    ReceiptLine? candidateLine,
    OrphanRecoveryRule rule = OrphanRecoveryRule.none,
  }) =>
      OrphanRecoveryAttempt(
        originalOrphanId: orphan.id,
        sourceElementIds: orphan.referencedElementIds,
        candidateLineId: candidateLine?.id,
        candidateProductElementId: candidateLine?.productElementId ??
            diagnostic?.candidateProductElementId,
        sameRow: diagnostic?.sameRow,
        sameColumn: diagnostic?.sameColumn,
        horizontalGap: diagnostic?.horizontalGap,
        verticalDistance: diagnostic?.verticalDistance,
        verticalOverlap: diagnostic?.verticalOverlap,
        rule: rule,
        confidence: OrphanRecoveryConfidence.none,
        outcome: OrphanRecoveryOutcome.unrecoverable,
        decisionReason: reason,
        recoveredLineId: null,
        recoveredCompleteness: null,
        summary: summary,
      );

  bool _isRecoverableRole(ReceiptElementType type) => switch (type) {
        ReceiptElementType.price ||
        ReceiptElementType.quantity ||
        ReceiptElementType.discount ||
        ReceiptElementType.tax ||
        ReceiptElementType.total =>
          true,
        _ => false,
      };

  int _compatibleCandidateCount({
    required String sourceId,
    required ReceiptElementType role,
    required bool sameRow,
    required List<ReceiptLine> productLines,
    required Map<String, ReceiptElementSpatialTrace> placements,
  }) {
    final sourcePlacement = placements[sourceId];
    if (sourcePlacement == null) return 0;
    return productLines.where((line) {
      if (!_roleIsAvailable(line, role)) return false;
      final productId = line.productElementId;
      final productPlacement = productId == null ? null : placements[productId];
      if (productPlacement == null) return false;
      return sameRow
          ? productPlacement.rowIndex == sourcePlacement.rowIndex
          : productPlacement.columnIndex == sourcePlacement.columnIndex;
    }).length;
  }

  bool _roleIsAvailable(ReceiptLine line, ReceiptElementType role) =>
      switch (role) {
        ReceiptElementType.price => line.priceElementId == null,
        ReceiptElementType.quantity => line.quantityElementId == null,
        ReceiptElementType.discount => line.discountElementId == null,
        ReceiptElementType.tax => line.taxElementId == null,
        ReceiptElementType.total => line.lineTotalElementId == null,
        _ => false,
      };
}

class _RecoveryProposal {
  const _RecoveryProposal({
    required this.orphan,
    required this.source,
    required this.target,
    required this.diagnostic,
    required this.role,
    required this.rule,
  });

  final ReceiptLine orphan;
  final ReceiptElement source;
  final ReceiptLine target;
  final OrphanLineDiagnostic diagnostic;
  final ReceiptElementType role;
  final OrphanRecoveryRule rule;
}

class _ProposalDecision {
  const _ProposalDecision._({this.proposal, this.attempt});

  const _ProposalDecision.proposal(_RecoveryProposal proposal)
      : this._(proposal: proposal);

  const _ProposalDecision.attempt(OrphanRecoveryAttempt attempt)
      : this._(attempt: attempt);

  final _RecoveryProposal? proposal;
  final OrphanRecoveryAttempt? attempt;
}
