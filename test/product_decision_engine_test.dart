import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching_v2/application/product_decision_service.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_decision.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_candidate.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_evidence.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_reason.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_result.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_trace.dart';
import 'package:maqadi_v2/product_matching_v2/engine/product_decision_engine.dart';

void main() {
  const engine = ProductDecisionEngine();

  test('selects a single clear winner deterministically', () {
    final result = engine.decide(_ranked([
      _candidate('winner', score: 0.95, exact: true),
      _candidate('runner', score: 0.30),
    ]));

    expect(result.matchedProduct?.productId, 'winner');
    expect(result.winningCandidate?.productId, 'winner');
    expect(result.trace.winningCandidate?.productId, 'winner');
    expect(result.trace.runnerUpCandidate?.productId, 'runner');
    expect(
      result.trace.rejectedCandidates.map((candidate) => candidate.productId),
      ['runner'],
    );
    expect(result.finalConfidence, 0.8825);
    expect(result.decisionStatus, ProductDecisionStatus.matched);
    expect(result.status, ProductMatchStatus.matched);
    expect(result.decisionReason, ProductMatchReason.clearWinner);
  });

  test('keeps tied leaders ambiguous without selecting either', () {
    final result = engine.decide(_ranked([
      _candidate('first', score: 0.80, exact: true),
      _candidate('second', score: 0.80, exact: true),
    ]));

    expect(result.matchedProduct, isNull);
    expect(result.trace.winningCandidate, isNull);
    expect(result.trace.runnerUpCandidate?.productId, 'second');
    expect(result.decisionStatus, ProductDecisionStatus.ambiguous);
    expect(result.decisionReason, ProductMatchReason.tie);
  });

  test('returns needs review when ranking evidence is insufficient', () {
    final result = engine.decide(_ranked([
      _candidate('weak', score: 0.40),
    ]));

    expect(result.matchedProduct, isNull);
    expect(result.trace.winningCandidate, isNull);
    expect(result.finalConfidence, 0.64);
    expect(result.decisionStatus, ProductDecisionStatus.needsReview);
    expect(result.status, ProductMatchStatus.lowConfidence);
    expect(result.decisionReason, ProductMatchReason.insufficientEvidence);
  });

  test('returns no match for an empty ranked candidate list', () {
    final result = engine.decide(_ranked(const []));

    expect(result.candidates, isEmpty);
    expect(result.matchedProduct, isNull);
    expect(result.finalConfidence, 0);
    expect(result.decisionStatus, ProductDecisionStatus.noMatch);
    expect(result.status, ProductMatchStatus.noMatch);
    expect(result.decisionReason, ProductMatchReason.noCandidates);
    expect(result.trace.confidenceCalculation!.finalConfidence, 0);
  });

  test('confidence records score separation and evidence contributions', () {
    final result = engine.decide(_ranked([
      _candidate('winner', score: 0.90, exact: true),
      _candidate('runner', score: 0.75),
    ]));
    final confidence = result.trace.confidenceCalculation!;

    expect(confidence.rankingScore, 0.90);
    expect(confidence.runnerUpScore, 0.75);
    expect(confidence.separation, 0.15);
    expect(confidence.evidenceQuality, 1);
    expect(confidence.rankingScoreWeight, 0.60);
    expect(confidence.separationWeight, 0.25);
    expect(confidence.evidenceQualityWeight, 0.15);
    expect(confidence.finalConfidence, 0.7275);
  });

  test('completed decision and confidence trace serialize stably', () {
    final result = engine.decide(_ranked([
      _candidate('winner', score: 0.95, exact: true),
      _candidate('runner', score: 0.30),
    ]));

    final restored = ProductMatchResult.fromJson(result.toJson());

    expect(restored.toJson(), result.toJson());
    expect(restored.decisionStatus, ProductDecisionStatus.matched);
    expect(restored.trace.decisionStatus, ProductDecisionStatus.matched);
    expect(restored.trace.finalDecision, ProductMatchReason.clearWinner);
    expect(restored.trace.winningCandidate?.productId, 'winner');
    expect(restored.trace.runnerUpCandidate?.productId, 'runner');
    expect(restored.trace.evidence['selection'], 'performed');
  });

  test('decision service is deterministic and does not reorder candidates', () {
    const service = ProductDecisionService();
    final input = _ranked([
      _candidate('first', score: 0.90, exact: true),
      _candidate('second', score: 0.70),
    ]);

    final first = service.decide(input);
    final second = service.decide(input);

    expect(first.toJson(), second.toJson());
    expect(first.candidates.map((value) => value.productId), [
      'first',
      'second',
    ]);
  });
}

ProductMatchResult _ranked(List<ProductMatchCandidate> candidates) =>
    ProductMatchResult(
      receiptLineId: 'line-1',
      matchedProduct: null,
      candidates: candidates,
      finalConfidence: null,
      status: ProductMatchStatus.pending,
      decisionReason: ProductMatchReason.notEvaluated,
      trace: ProductMatchTrace(
        evaluationOrder: candidates.map((value) => value.productId),
        candidateRanking: candidates,
        winningCandidate: null,
        rejectedCandidates: const [],
        evidence: const {
          'ranking': 'performed',
          'selection': 'notPerformed',
        },
        finalDecision: ProductMatchReason.notEvaluated,
        candidateOrderBeforeRanking: candidates.map((value) => value.productId),
        candidateOrderAfterRanking: candidates.map((value) => value.productId),
      ),
    );

ProductMatchCandidate _candidate(
  String id, {
  required double score,
  bool exact = false,
}) =>
    ProductMatchCandidate(
      productId: id,
      displayName: id,
      matchingScore: score,
      confidence: 0,
      evidence: ProductMatchEvidence(
        normalizedQuery: 'milk',
        normalizedCatalogText: exact ? 'milk' : 'milk powder',
        matchedTokens: const ['milk'],
        exactNormalizedMatch: exact,
        discoverySource: ProductMatchDiscoverySource.catalogName,
        matchedCatalogText: exact ? 'milk' : 'milk powder',
      ),
      matchReason: exact
          ? ProductMatchReason.exactMatch
          : ProductMatchReason.normalizedMatch,
    );
