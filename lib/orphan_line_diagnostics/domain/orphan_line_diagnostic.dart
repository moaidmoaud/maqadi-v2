import '../../receipt_understanding/domain/receipt_element_type.dart';

enum OrphanLineReason {
  noProductElement,
  noPriceElement,
  failedRowGrouping,
  failedColumnGrouping,
  distanceTooLarge,
  overlapTooSmall,
  multipleCompetingCandidates,
  unknown,
}

enum OrphanRecoveryPossibility { yes, maybe, no }

class OrphanSourceElement {
  const OrphanSourceElement({
    required this.id,
    required this.text,
    required this.type,
  });

  factory OrphanSourceElement.fromJson(Map<String, Object?> json) =>
      OrphanSourceElement(
        id: json['id']! as String,
        text: json['text']! as String,
        type: ReceiptElementType.values.byName(json['type']! as String),
      );

  final String id;
  final String text;
  final ReceiptElementType type;

  Map<String, Object> toJson() => {
        'id': id,
        'text': text,
        'type': type.name,
      };
}

class OrphanLineDiagnostic {
  OrphanLineDiagnostic({
    required this.orphanId,
    required Iterable<OrphanSourceElement> sourceElements,
    required this.productElementExists,
    required this.priceElementExists,
    required this.quantityElementExists,
    required this.candidateProductElementId,
    required this.sameRow,
    required this.sameColumn,
    required this.horizontalGap,
    required this.verticalDistance,
    required this.verticalOverlap,
    required this.rejectionReason,
    required this.recoveryPossibility,
    required this.recoveryReason,
    required this.groupingAttemptSummary,
  }) : sourceElements = List.unmodifiable(sourceElements);

  factory OrphanLineDiagnostic.fromJson(Map<String, Object?> json) =>
      OrphanLineDiagnostic(
        orphanId: json['orphanId']! as String,
        sourceElements: (json['sourceElements']! as List<Object?>).map(
          (value) => OrphanSourceElement.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
        productElementExists: json['productElementExists']! as bool,
        priceElementExists: json['priceElementExists']! as bool,
        quantityElementExists: json['quantityElementExists']! as bool,
        candidateProductElementId: json['candidateProductElementId'] as String?,
        sameRow: json['sameRow'] as bool?,
        sameColumn: json['sameColumn'] as bool?,
        horizontalGap: (json['horizontalGap'] as num?)?.toDouble(),
        verticalDistance: (json['verticalDistance'] as num?)?.toDouble(),
        verticalOverlap: (json['verticalOverlap'] as num?)?.toDouble(),
        rejectionReason: OrphanLineReason.values.byName(
          json['rejectionReason']! as String,
        ),
        recoveryPossibility: OrphanRecoveryPossibility.values.byName(
          json['recoveryPossibility']! as String,
        ),
        recoveryReason: json['recoveryReason']! as String,
        groupingAttemptSummary: json['groupingAttemptSummary']! as String,
      );

  final String orphanId;
  final List<OrphanSourceElement> sourceElements;
  final bool productElementExists;
  final bool priceElementExists;
  final bool quantityElementExists;
  final String? candidateProductElementId;
  final bool? sameRow;
  final bool? sameColumn;
  final double? horizontalGap;
  final double? verticalDistance;
  final double? verticalOverlap;
  final OrphanLineReason rejectionReason;
  final OrphanRecoveryPossibility recoveryPossibility;
  final String recoveryReason;
  final String groupingAttemptSummary;

  Map<String, Object?> toJson() => {
        'orphanId': orphanId,
        'sourceElements': [
          for (final element in sourceElements) element.toJson(),
        ],
        'productElementExists': productElementExists,
        'priceElementExists': priceElementExists,
        'quantityElementExists': quantityElementExists,
        'candidateProductElementId': candidateProductElementId,
        'sameRow': sameRow,
        'sameColumn': sameColumn,
        'horizontalGap': horizontalGap,
        'verticalDistance': verticalDistance,
        'verticalOverlap': verticalOverlap,
        'rejectionReason': rejectionReason.name,
        'recoveryPossibility': recoveryPossibility.name,
        'recoveryReason': recoveryReason,
        'groupingAttemptSummary': groupingAttemptSummary,
      };
}

class OrphanRecoverySummary {
  const OrphanRecoverySummary({
    required this.recoverable,
    required this.maybeRecoverable,
    required this.unrecoverable,
  });

  const OrphanRecoverySummary.empty()
      : recoverable = 0,
        maybeRecoverable = 0,
        unrecoverable = 0;

  factory OrphanRecoverySummary.fromDiagnostics(
    Iterable<OrphanLineDiagnostic> diagnostics,
  ) =>
      OrphanRecoverySummary(
        recoverable: diagnostics
            .where((value) =>
                value.recoveryPossibility == OrphanRecoveryPossibility.yes)
            .length,
        maybeRecoverable: diagnostics
            .where((value) =>
                value.recoveryPossibility == OrphanRecoveryPossibility.maybe)
            .length,
        unrecoverable: diagnostics
            .where((value) =>
                value.recoveryPossibility == OrphanRecoveryPossibility.no)
            .length,
      );

  factory OrphanRecoverySummary.fromJson(Map<String, Object?> json) =>
      OrphanRecoverySummary(
        recoverable: json['recoverable']! as int,
        maybeRecoverable: json['maybeRecoverable']! as int,
        unrecoverable: json['unrecoverable']! as int,
      );

  final int recoverable;
  final int maybeRecoverable;
  final int unrecoverable;

  int get total => recoverable + maybeRecoverable + unrecoverable;

  Map<String, int> toJson() => {
        'recoverable': recoverable,
        'maybeRecoverable': maybeRecoverable,
        'unrecoverable': unrecoverable,
      };
}
