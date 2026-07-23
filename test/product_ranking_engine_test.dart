import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching_v2/application/product_ranking_service.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_candidate.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_evidence.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_reason.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_result.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_trace.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_ranking_evidence.dart';
import 'package:maqadi_v2/product_matching_v2/engine/product_ranking_engine.dart';

void main() {
  const engine = ProductRankingEngine();

  test('ranks exact canonical match above shared-token candidates', () {
    final result = engine.rank(_result([
      _candidate(
        'shared',
        query: 'fresh milk',
        catalogText: 'milk powder',
        matchedTokens: const ['milk'],
      ),
      _candidate(
        'exact',
        query: 'fresh milk',
        catalogText: 'fresh milk',
        matchedTokens: const ['fresh', 'milk'],
        exact: true,
      ),
    ]));

    expect(result.candidates.map((value) => value.productId), [
      'exact',
      'shared',
    ]);
    expect(result.candidates[0].matchingScore, 0.95);
    expect(result.candidates[1].matchingScore, 0.3);
  });

  test('exact alias ranks above a shared-token alias', () {
    final result = engine.rank(_result([
      _candidate(
        'shared',
        query: 'garlic bag',
        catalogText: 'potatoes bag',
        matchedTokens: const ['bag'],
        source: ProductMatchDiscoverySource.catalogAlias,
        matchedAlias: 'potatoes bag',
      ),
      _candidate(
        'exact',
        query: 'garlic bag',
        catalogText: 'garlic bag',
        matchedTokens: const ['garlic', 'bag'],
        exact: true,
        source: ProductMatchDiscoverySource.catalogAlias,
        matchedAlias: 'garlic bag',
      ),
    ]));

    expect(result.candidates.map((value) => value.productId), [
      'exact',
      'shared',
    ]);
    expect(result.candidates.first.matchingScore, 0.9);
    expect(
      result.trace.rankingEvidence['exact']!.factors
          .singleWhere(
            (value) => value.type == ProductRankingFactorType.aliasSpecificity,
          )
          .value,
      1,
    );
  });

  test('shared-token coverage contributes proportionally to score', () {
    final result = engine.rank(_result([
      _candidate(
        'one-token',
        query: 'fresh whole milk',
        catalogText: 'milk powder',
        matchedTokens: const ['milk'],
      ),
      _candidate(
        'two-token',
        query: 'fresh whole milk',
        catalogText: 'fresh milk',
        matchedTokens: const ['fresh', 'milk'],
      ),
    ]));

    expect(result.candidates.first.productId, 'two-token');
    final oneToken = result.trace.rankingEvidence['one-token']!;
    final twoToken = result.trace.rankingEvidence['two-token']!;
    expect(twoToken.finalScore, greaterThan(oneToken.finalScore));
    expect(
      twoToken.factors
          .singleWhere(
            (value) => value.type == ProductRankingFactorType.tokenCoverage,
          )
          .value,
      0.666667,
    );
  });

  test('stable ordering preserves input order for tied scores', () {
    final result = engine.rank(_result([
      _candidate(
        'first',
        query: 'milk',
        catalogText: 'milk powder',
        matchedTokens: const ['milk'],
      ),
      _candidate(
        'second',
        query: 'milk',
        catalogText: 'milk carton',
        matchedTokens: const ['milk'],
      ),
      _candidate(
        'third',
        query: 'milk',
        catalogText: 'milk bottle',
        matchedTokens: const ['milk'],
      ),
    ]));

    expect(result.candidates.map((value) => value.productId), [
      'first',
      'second',
      'third',
    ]);
  });

  test('ties retain equal scores and equal ranks without a winner', () {
    final result = engine.rank(_result([
      _candidate(
        'first',
        query: 'milk',
        catalogText: 'milk powder',
        matchedTokens: const ['milk'],
      ),
      _candidate(
        'second',
        query: 'milk',
        catalogText: 'milk carton',
        matchedTokens: const ['milk'],
      ),
    ]));

    expect(
        result.candidates[0].matchingScore, result.candidates[1].matchingScore);
    expect(result.trace.rankingEvidence['first']!.rank, 1);
    expect(result.trace.rankingEvidence['second']!.rank, 1);
    expect(result.matchedProduct, isNull);
    expect(result.finalConfidence, isNull);
    expect(result.trace.winningCandidate, isNull);
    expect(result.decisionReason, ProductMatchReason.notEvaluated);
  });

  test('ranking score evidence and trace serialize stably', () {
    final result = engine.rank(_result([
      _candidate(
        'shared',
        query: 'fresh milk',
        catalogText: 'milk powder',
        matchedTokens: const ['milk'],
      ),
      _candidate(
        'exact',
        query: 'fresh milk',
        catalogText: 'fresh milk',
        matchedTokens: const ['fresh', 'milk'],
        exact: true,
      ),
    ]));

    final restored = ProductMatchResult.fromJson(result.toJson());

    expect(restored.toJson(), result.toJson());
    expect(restored.trace.candidateOrderBeforeRanking, ['shared', 'exact']);
    expect(restored.trace.candidateOrderAfterRanking, ['exact', 'shared']);
    expect(restored.trace.candidateRanking.map((value) => value.productId), [
      'exact',
      'shared',
    ]);
    expect(restored.trace.rankingEvidence['exact']!.finalScore, 0.95);
    expect(restored.trace.evidence['selection'], 'notPerformed');
  });

  test('ranking service delegates deterministically without selecting', () {
    const service = ProductRankingService();
    final input = _result([
      _candidate(
        'exact',
        query: 'milk',
        catalogText: 'milk',
        matchedTokens: const ['milk'],
        exact: true,
      ),
    ]);

    final first = service.rank(input);
    final second = service.rank(input);

    expect(first.toJson(), second.toJson());
    expect(first.matchedProduct, isNull);
    expect(first.trace.winningCandidate, isNull);
  });
}

ProductMatchResult _result(List<ProductMatchCandidate> candidates) =>
    ProductMatchResult(
      receiptLineId: 'line-1',
      matchedProduct: null,
      candidates: candidates,
      finalConfidence: null,
      status: ProductMatchStatus.pending,
      decisionReason: ProductMatchReason.notEvaluated,
      trace: ProductMatchTrace(
        evaluationOrder: candidates.map((value) => value.productId),
        candidateRanking: const [],
        winningCandidate: null,
        rejectedCandidates: const [],
        evidence: const {
          'stage': 'candidateGeneration',
          'ranking': 'notPerformed',
          'selection': 'notPerformed',
        },
        finalDecision: ProductMatchReason.notEvaluated,
        normalizedQuery:
            candidates.isEmpty ? '' : candidates.first.evidence.normalizedQuery,
        generatedCandidateCount: candidates.length,
        generatedCandidateIds: candidates.map((value) => value.productId),
        generationOrder: candidates.map((value) => value.productId),
        discoveryEvidence: {
          for (final candidate in candidates)
            candidate.productId: candidate.evidence,
        },
      ),
    );

ProductMatchCandidate _candidate(
  String id, {
  required String query,
  required String catalogText,
  required List<String> matchedTokens,
  bool exact = false,
  ProductMatchDiscoverySource source = ProductMatchDiscoverySource.catalogName,
  String? matchedAlias,
}) =>
    ProductMatchCandidate(
      productId: id,
      displayName: id,
      matchingScore: 0,
      confidence: 0,
      evidence: ProductMatchEvidence(
        normalizedQuery: query,
        normalizedCatalogText: catalogText,
        matchedTokens: matchedTokens,
        exactNormalizedMatch: exact,
        discoverySource: source,
        matchedCatalogText: matchedAlias ?? catalogText,
        matchedAlias: matchedAlias,
      ),
      matchReason: exact
          ? ProductMatchReason.exactMatch
          : ProductMatchReason.normalizedMatch,
    );
