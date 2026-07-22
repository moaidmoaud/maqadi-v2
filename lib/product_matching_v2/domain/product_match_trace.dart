import 'product_match_candidate.dart';
import 'product_match_reason.dart';

class ProductMatchTrace {
  ProductMatchTrace({
    required Iterable<String> evaluationOrder,
    required Iterable<ProductMatchCandidate> candidateRanking,
    required this.winningCandidate,
    required Iterable<ProductMatchCandidate> rejectedCandidates,
    required Map<String, String> evidence,
    required this.finalDecision,
  })  : evaluationOrder = List.unmodifiable(evaluationOrder),
        candidateRanking = List.unmodifiable(candidateRanking),
        rejectedCandidates = List.unmodifiable(rejectedCandidates),
        evidence = Map.unmodifiable(evidence);

  factory ProductMatchTrace.fromJson(Map<String, Object?> json) =>
      ProductMatchTrace(
        evaluationOrder: (json['evaluationOrder']! as List<Object?>).cast(),
        candidateRanking: (json['candidateRanking']! as List<Object?>).map(
          (value) => ProductMatchCandidate.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
        winningCandidate: json['winningCandidate'] == null
            ? null
            : ProductMatchCandidate.fromJson(
                json['winningCandidate']! as Map<String, Object?>,
              ),
        rejectedCandidates: (json['rejectedCandidates']! as List<Object?>).map(
          (value) => ProductMatchCandidate.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
        evidence: (json['evidence']! as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key! as String, value! as String),
        ),
        finalDecision: ProductMatchReason.values.byName(
          json['finalDecision']! as String,
        ),
      );

  final List<String> evaluationOrder;
  final List<ProductMatchCandidate> candidateRanking;
  final ProductMatchCandidate? winningCandidate;
  final List<ProductMatchCandidate> rejectedCandidates;
  final Map<String, String> evidence;
  final ProductMatchReason finalDecision;

  Map<String, Object?> toJson() => {
        'evaluationOrder': evaluationOrder,
        'candidateRanking': [
          for (final value in candidateRanking) value.toJson(),
        ],
        'winningCandidate': winningCandidate?.toJson(),
        'rejectedCandidates': [
          for (final value in rejectedCandidates) value.toJson(),
        ],
        'evidence': evidence,
        'finalDecision': finalDecision.name,
      };
}
