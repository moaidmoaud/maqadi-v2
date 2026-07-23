import '../../receipt_line_builder/domain/receipt_line.dart';
import '../../receipt_line_builder/domain/receipt_line_completeness.dart';

enum OrphanRecoveryOutcome {
  recoveredComplete,
  recoveredPartial,
  unrecoverable,
}

enum OrphanRecoveryRule {
  sameRowNearestProduct,
  sameColumnNearestProduct,
  none,
}

enum OrphanRecoveryConfidence { high, moderate, none }

enum OrphanRecoveryDecisionReason {
  recoveredUniqueSameRow,
  recoveredUniqueSameColumn,
  noProductCandidate,
  geometryUnavailable,
  spatialRelationshipInsufficient,
  roleAlreadyAssigned,
  multipleProductCandidates,
  competingOrphans,
  unsupportedOrphanRole,
}

class OrphanRecoveryAttempt {
  OrphanRecoveryAttempt({
    required this.originalOrphanId,
    required Iterable<String> sourceElementIds,
    required this.candidateLineId,
    required this.candidateProductElementId,
    required this.sameRow,
    required this.sameColumn,
    required this.horizontalGap,
    required this.verticalDistance,
    required this.verticalOverlap,
    required this.rule,
    required this.confidence,
    required this.outcome,
    required this.decisionReason,
    required this.recoveredLineId,
    required this.recoveredCompleteness,
    required this.summary,
  }) : sourceElementIds = List.unmodifiable(sourceElementIds);

  factory OrphanRecoveryAttempt.fromJson(Map<String, Object?> json) =>
      OrphanRecoveryAttempt(
        originalOrphanId: json['originalOrphanId']! as String,
        sourceElementIds:
            (json['sourceElementIds']! as List<Object?>).cast<String>(),
        candidateLineId: json['candidateLineId'] as String?,
        candidateProductElementId: json['candidateProductElementId'] as String?,
        sameRow: json['sameRow'] as bool?,
        sameColumn: json['sameColumn'] as bool?,
        horizontalGap: (json['horizontalGap'] as num?)?.toDouble(),
        verticalDistance: (json['verticalDistance'] as num?)?.toDouble(),
        verticalOverlap: (json['verticalOverlap'] as num?)?.toDouble(),
        rule: OrphanRecoveryRule.values.byName(json['rule']! as String),
        confidence: OrphanRecoveryConfidence.values.byName(
          json['confidence']! as String,
        ),
        outcome:
            OrphanRecoveryOutcome.values.byName(json['outcome']! as String),
        decisionReason: OrphanRecoveryDecisionReason.values.byName(
          json['decisionReason']! as String,
        ),
        recoveredLineId: json['recoveredLineId'] as String?,
        recoveredCompleteness: json['recoveredCompleteness'] == null
            ? null
            : ReceiptLineCompleteness.values.byName(
                json['recoveredCompleteness']! as String,
              ),
        summary: json['summary']! as String,
      );

  final String originalOrphanId;
  final List<String> sourceElementIds;
  final String? candidateLineId;
  final String? candidateProductElementId;
  final bool? sameRow;
  final bool? sameColumn;
  final double? horizontalGap;
  final double? verticalDistance;
  final double? verticalOverlap;
  final OrphanRecoveryRule rule;
  final OrphanRecoveryConfidence confidence;
  final OrphanRecoveryOutcome outcome;
  final OrphanRecoveryDecisionReason decisionReason;
  final String? recoveredLineId;
  final ReceiptLineCompleteness? recoveredCompleteness;
  final String summary;

  bool get recovered => outcome != OrphanRecoveryOutcome.unrecoverable;

  Map<String, Object?> toJson() => {
        'originalOrphanId': originalOrphanId,
        'sourceElementIds': sourceElementIds,
        'candidateLineId': candidateLineId,
        'candidateProductElementId': candidateProductElementId,
        'sameRow': sameRow,
        'sameColumn': sameColumn,
        'horizontalGap': horizontalGap,
        'verticalDistance': verticalDistance,
        'verticalOverlap': verticalOverlap,
        'rule': rule.name,
        'confidence': confidence.name,
        'outcome': outcome.name,
        'decisionReason': decisionReason.name,
        'recoveredLineId': recoveredLineId,
        'recoveredCompleteness': recoveredCompleteness?.name,
        'summary': summary,
      };
}

class OrphanLineRecoveryResult {
  OrphanLineRecoveryResult({
    required Iterable<ReceiptLine> lines,
    required Iterable<OrphanRecoveryAttempt> attempts,
  })  : lines = List.unmodifiable(lines),
        attempts = List.unmodifiable(attempts);

  final List<ReceiptLine> lines;
  final List<OrphanRecoveryAttempt> attempts;

  int get recoveredOrphanCount =>
      attempts.where((attempt) => attempt.recovered).length;

  int get remainingOrphanCount => lines
      .where((line) => line.completeness == ReceiptLineCompleteness.orphan)
      .length;
}
