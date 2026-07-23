import '../domain/product_decision.dart';
import '../domain/product_match_candidate.dart';
import '../domain/product_match_evidence.dart';
import '../domain/product_match_reason.dart';
import '../domain/product_match_result.dart';
import '../domain/product_match_trace.dart';

class ProductDecisionEngine {
  const ProductDecisionEngine();

  ProductMatchResult decide(ProductMatchResult ranked) {
    if (ranked.candidates.isEmpty) {
      return _complete(
        ranked,
        winner: null,
        runnerUp: null,
        confidence: _emptyConfidence,
        status: ProductDecisionStatus.noMatch,
        reason: ProductMatchReason.noCandidates,
      );
    }

    final leader = ranked.candidates.first;
    final runnerUp = ranked.candidates.length > 1 ? ranked.candidates[1] : null;
    final confidence = _confidence(leader, runnerUp);
    if (runnerUp != null && leader.matchingScore == runnerUp.matchingScore) {
      return _complete(
        ranked,
        winner: null,
        runnerUp: runnerUp,
        confidence: confidence,
        status: ProductDecisionStatus.ambiguous,
        reason: ProductMatchReason.tie,
      );
    }
    if (leader.matchingScore < _minimumRankingScore ||
        confidence.finalConfidence < _minimumFinalConfidence) {
      return _complete(
        ranked,
        winner: null,
        runnerUp: runnerUp,
        confidence: confidence,
        status: ProductDecisionStatus.needsReview,
        reason: ProductMatchReason.insufficientEvidence,
      );
    }
    return _complete(
      ranked,
      winner: leader,
      runnerUp: runnerUp,
      confidence: confidence,
      status: ProductDecisionStatus.matched,
      reason: ProductMatchReason.clearWinner,
    );
  }

  ProductConfidenceCalculation _confidence(
    ProductMatchCandidate leader,
    ProductMatchCandidate? runnerUp,
  ) {
    final runnerUpScore = runnerUp?.matchingScore;
    final separation = runnerUpScore == null
        ? 1.0
        : (leader.matchingScore - runnerUpScore).clamp(0.0, 1.0);
    final evidenceQuality = _evidenceQuality(leader.evidence);
    final finalConfidence = _round(
      (leader.matchingScore * _rankingScoreWeight) +
          (separation * _separationWeight) +
          (evidenceQuality * _evidenceQualityWeight),
    );
    return ProductConfidenceCalculation(
      rankingScore: leader.matchingScore,
      runnerUpScore: runnerUpScore,
      separation: _round(separation),
      evidenceQuality: evidenceQuality,
      rankingScoreWeight: _rankingScoreWeight,
      separationWeight: _separationWeight,
      evidenceQualityWeight: _evidenceQualityWeight,
      finalConfidence: finalConfidence,
    );
  }

  double _evidenceQuality(ProductMatchEvidence evidence) {
    if (evidence.exactNormalizedMatch) return 1;
    final queryTokens =
        evidence.normalizedQuery.split(' ').where((value) => value.isNotEmpty);
    final queryTokenCount = queryTokens.toSet().length;
    final tokenCoverage = queryTokenCount == 0
        ? 0.0
        : evidence.matchedTokens.toSet().length / queryTokenCount;
    final sourceQuality =
        evidence.discoverySource == ProductMatchDiscoverySource.catalogName
            ? 1.0
            : 0.9;
    return _round(
      (tokenCoverage * _evidenceTokenWeight) +
          (sourceQuality * _evidenceSourceWeight),
    );
  }

  ProductMatchResult _complete(
    ProductMatchResult ranked, {
    required ProductMatchCandidate? winner,
    required ProductMatchCandidate? runnerUp,
    required ProductConfidenceCalculation confidence,
    required ProductDecisionStatus status,
    required ProductMatchReason reason,
  }) {
    final trace = ranked.trace;
    return ProductMatchResult(
      receiptLineId: ranked.receiptLineId,
      matchedProduct: winner,
      candidates: ranked.candidates,
      finalConfidence: confidence.finalConfidence,
      status: _legacyStatus(status),
      decisionReason: reason,
      decisionStatus: status,
      trace: ProductMatchTrace(
        evaluationOrder: trace.evaluationOrder,
        candidateRanking: trace.candidateRanking,
        winningCandidate: winner,
        rejectedCandidates: [
          for (final candidate in ranked.candidates)
            if (candidate.productId != winner?.productId) candidate,
        ],
        evidence: {
          ...trace.evidence,
          'selection': 'performed',
          'decisionStatus': status.name,
          'decisionReason': reason.name,
        },
        finalDecision: reason,
        normalizedQuery: trace.normalizedQuery,
        generatedCandidateCount: trace.generatedCandidateCount,
        generatedCandidateIds: trace.generatedCandidateIds,
        generationOrder: trace.generationOrder,
        discoveryEvidence: trace.discoveryEvidence,
        originalQueryText: trace.originalQueryText,
        preCorrectionNormalizedQuery: trace.preCorrectionNormalizedQuery,
        appliedNormalizationOperations: trace.appliedNormalizationOperations,
        candidateGenerationDiagnostics: trace.candidateGenerationDiagnostics,
        candidateOrderBeforeRanking: trace.candidateOrderBeforeRanking,
        candidateOrderAfterRanking: trace.candidateOrderAfterRanking,
        rankingEvidence: trace.rankingEvidence,
        runnerUpCandidate: runnerUp,
        confidenceCalculation: confidence,
        decisionStatus: status,
      ),
    );
  }

  ProductMatchStatus _legacyStatus(ProductDecisionStatus status) =>
      switch (status) {
        ProductDecisionStatus.matched => ProductMatchStatus.matched,
        ProductDecisionStatus.needsReview => ProductMatchStatus.lowConfidence,
        ProductDecisionStatus.ambiguous => ProductMatchStatus.ambiguous,
        ProductDecisionStatus.noMatch => ProductMatchStatus.noMatch,
      };

  double _round(double value) =>
      (value * _confidencePrecision).round() / _confidencePrecision;

  static const ProductConfidenceCalculation _emptyConfidence =
      ProductConfidenceCalculation(
    rankingScore: 0,
    runnerUpScore: null,
    separation: 0,
    evidenceQuality: 0,
    rankingScoreWeight: _rankingScoreWeight,
    separationWeight: _separationWeight,
    evidenceQualityWeight: _evidenceQualityWeight,
    finalConfidence: 0,
  );
  static const double _minimumRankingScore = 0.60;
  static const double _minimumFinalConfidence = 0.60;
  static const double _rankingScoreWeight = 0.60;
  static const double _separationWeight = 0.25;
  static const double _evidenceQualityWeight = 0.15;
  static const double _evidenceTokenWeight = 0.80;
  static const double _evidenceSourceWeight = 0.20;
  static const double _confidencePrecision = 1000000;
}
