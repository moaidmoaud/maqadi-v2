import '../domain/product_match_candidate.dart';
import '../domain/product_match_evidence.dart';
import '../domain/product_match_reason.dart';
import '../domain/product_match_result.dart';
import '../domain/product_match_trace.dart';
import '../domain/product_ranking_evidence.dart';

class ProductRankingEngine {
  const ProductRankingEngine();

  ProductMatchResult rank(ProductMatchResult input) {
    final scored = <_ScoredCandidate>[];
    for (var index = 0; index < input.candidates.length; index++) {
      scored.add(_score(input.candidates[index], index));
    }
    scored.sort((left, right) {
      final scoreOrder = right.score.compareTo(left.score);
      return scoreOrder != 0
          ? scoreOrder
          : left.originalOrder.compareTo(right.originalOrder);
    });

    final rankedCandidates = <ProductMatchCandidate>[];
    final rankingEvidence = <String, ProductCandidateRankingEvidence>{};
    double? previousScore;
    var previousRank = 0;
    for (var index = 0; index < scored.length; index++) {
      final value = scored[index];
      final rank = previousScore == value.score ? previousRank : index + 1;
      previousScore = value.score;
      previousRank = rank;
      final candidate = ProductMatchCandidate(
        productId: value.candidate.productId,
        displayName: value.candidate.displayName,
        matchingScore: value.score,
        confidence: value.candidate.confidence,
        evidence: value.candidate.evidence,
        matchReason: value.candidate.matchReason,
      );
      rankedCandidates.add(candidate);
      rankingEvidence[candidate.productId] = ProductCandidateRankingEvidence(
        productId: candidate.productId,
        originalOrder: value.originalOrder,
        rank: rank,
        finalScore: value.score,
        factors: value.factors,
      );
    }

    final trace = input.trace;
    return ProductMatchResult(
      receiptLineId: input.receiptLineId,
      matchedProduct: null,
      candidates: rankedCandidates,
      finalConfidence: null,
      status: ProductMatchStatus.pending,
      decisionReason: ProductMatchReason.notEvaluated,
      trace: ProductMatchTrace(
        evaluationOrder: trace.evaluationOrder,
        candidateRanking: rankedCandidates,
        winningCandidate: null,
        rejectedCandidates: trace.rejectedCandidates,
        evidence: {
          ...trace.evidence,
          'ranking': 'performed',
          'selection': 'notPerformed',
        },
        finalDecision: ProductMatchReason.notEvaluated,
        normalizedQuery: trace.normalizedQuery,
        generatedCandidateCount: trace.generatedCandidateCount,
        generatedCandidateIds: trace.generatedCandidateIds,
        generationOrder: trace.generationOrder,
        discoveryEvidence: trace.discoveryEvidence,
        originalQueryText: trace.originalQueryText,
        preCorrectionNormalizedQuery: trace.preCorrectionNormalizedQuery,
        appliedNormalizationOperations: trace.appliedNormalizationOperations,
        candidateGenerationDiagnostics: trace.candidateGenerationDiagnostics,
        candidateOrderBeforeRanking: input.candidates.map(
          (value) => value.productId,
        ),
        candidateOrderAfterRanking: rankedCandidates.map(
          (value) => value.productId,
        ),
        rankingEvidence: rankingEvidence,
      ),
    );
  }

  _ScoredCandidate _score(
    ProductMatchCandidate candidate,
    int originalOrder,
  ) {
    final evidence = candidate.evidence;
    final queryTokenCount = _tokens(evidence.normalizedQuery).length;
    final catalogTokenCount = _tokens(evidence.normalizedCatalogText).length;
    final matchedTokenCount = evidence.matchedTokens.toSet().length;
    final isAlias =
        evidence.discoverySource == ProductMatchDiscoverySource.catalogAlias;
    final factors = <ProductRankingFactor>[
      _factor(
        ProductRankingFactorType.exactNormalizedMatch,
        evidence.exactNormalizedMatch ? 1 : 0,
        _exactMatchWeight,
      ),
      _factor(
        ProductRankingFactorType.canonicalNameMatch,
        isAlias ? 0 : 1,
        _canonicalNameWeight,
      ),
      _factor(
        ProductRankingFactorType.aliasMatch,
        isAlias ? 1 : 0,
        _aliasMatchWeight,
      ),
      _factor(
        ProductRankingFactorType.tokenCoverage,
        queryTokenCount == 0 ? 0 : matchedTokenCount / queryTokenCount,
        _tokenCoverageWeight,
      ),
      _factor(
        ProductRankingFactorType.aliasSpecificity,
        !isAlias || catalogTokenCount == 0
            ? 0
            : matchedTokenCount / catalogTokenCount,
        _aliasSpecificityWeight,
      ),
    ];
    final score = _round(
      factors.fold<double>(0, (sum, value) => sum + value.contribution),
    );
    return _ScoredCandidate(
      candidate: candidate,
      originalOrder: originalOrder,
      score: score,
      factors: factors,
    );
  }

  ProductRankingFactor _factor(
    ProductRankingFactorType type,
    num value,
    double weight,
  ) {
    final normalizedValue = _round(value.toDouble().clamp(0, 1));
    return ProductRankingFactor(
      type: type,
      value: normalizedValue,
      weight: weight,
      contribution: _round(normalizedValue * weight),
    );
  }

  Set<String> _tokens(String value) =>
      value.split(' ').where((token) => token.isNotEmpty).toSet();

  double _round(double value) =>
      (value * _scorePrecision).round() / _scorePrecision;

  static const double _exactMatchWeight = 0.55;
  static const double _canonicalNameWeight = 0.20;
  static const double _aliasMatchWeight = 0.10;
  static const double _tokenCoverageWeight = 0.20;
  static const double _aliasSpecificityWeight = 0.05;
  static const double _scorePrecision = 1000000;
}

class _ScoredCandidate {
  const _ScoredCandidate({
    required this.candidate,
    required this.originalOrder,
    required this.score,
    required this.factors,
  });

  final ProductMatchCandidate candidate;
  final int originalOrder;
  final double score;
  final List<ProductRankingFactor> factors;
}
