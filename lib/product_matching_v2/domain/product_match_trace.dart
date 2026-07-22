import 'product_match_candidate.dart';
import 'product_match_evidence.dart';
import 'product_match_reason.dart';

class ProductMatchTrace {
  ProductMatchTrace({
    required Iterable<String> evaluationOrder,
    required Iterable<ProductMatchCandidate> candidateRanking,
    required this.winningCandidate,
    required Iterable<ProductMatchCandidate> rejectedCandidates,
    required Map<String, String> evidence,
    required this.finalDecision,
    this.normalizedQuery,
    this.generatedCandidateCount = 0,
    Iterable<String> generatedCandidateIds = const [],
    Iterable<String> generationOrder = const [],
    Map<String, ProductMatchEvidence> discoveryEvidence = const {},
  })  : evaluationOrder = List.unmodifiable(evaluationOrder),
        candidateRanking = List.unmodifiable(candidateRanking),
        rejectedCandidates = List.unmodifiable(rejectedCandidates),
        evidence = Map.unmodifiable(evidence),
        generatedCandidateIds = List.unmodifiable(generatedCandidateIds),
        generationOrder = List.unmodifiable(generationOrder),
        discoveryEvidence = Map.unmodifiable(discoveryEvidence);

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
        normalizedQuery: json['normalizedQuery'] as String?,
        generatedCandidateCount:
            (json['generatedCandidateCount'] as num?)?.toInt() ?? 0,
        generatedCandidateIds:
            (json['generatedCandidateIds'] as List<Object?>? ?? const [])
                .cast(),
        generationOrder:
            (json['generationOrder'] as List<Object?>? ?? const []).cast(),
        discoveryEvidence:
            (json['discoveryEvidence'] as Map<Object?, Object?>? ?? const {})
                .map(
          (key, value) => MapEntry(
            key! as String,
            ProductMatchEvidence.fromJson(value! as Map<String, Object?>),
          ),
        ),
      );

  final List<String> evaluationOrder;
  final List<ProductMatchCandidate> candidateRanking;
  final ProductMatchCandidate? winningCandidate;
  final List<ProductMatchCandidate> rejectedCandidates;
  final Map<String, String> evidence;
  final ProductMatchReason finalDecision;
  final String? normalizedQuery;
  final int generatedCandidateCount;
  final List<String> generatedCandidateIds;
  final List<String> generationOrder;
  final Map<String, ProductMatchEvidence> discoveryEvidence;

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
        'normalizedQuery': normalizedQuery,
        'generatedCandidateCount': generatedCandidateCount,
        'generatedCandidateIds': generatedCandidateIds,
        'generationOrder': generationOrder,
        'discoveryEvidence': {
          for (final entry in discoveryEvidence.entries)
            entry.key: entry.value.toJson(),
        },
      };
}
