import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_candidate.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_evidence.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_reason.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_result.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_trace.dart';

void main() {
  final candidate = ProductMatchCandidate(
    productId: 'product-1',
    displayName: 'Milk',
    matchingScore: 0.92,
    confidence: 0.88,
    evidence: ProductMatchEvidence(
      normalizedQuery: 'milk',
      normalizedCatalogText: 'milk',
      matchedTokens: const ['milk'],
      exactNormalizedMatch: true,
      discoverySource: ProductMatchDiscoverySource.catalogName,
    ),
    matchReason: ProductMatchReason.normalizedMatch,
  );
  final rejectedCandidate = ProductMatchCandidate(
    productId: 'product-2',
    displayName: 'Milk Powder',
    matchingScore: 0.5,
    confidence: 0.4,
    evidence: ProductMatchEvidence(
      normalizedQuery: 'milk',
      normalizedCatalogText: 'milk powder',
      matchedTokens: const ['milk'],
      exactNormalizedMatch: false,
      discoverySource: ProductMatchDiscoverySource.catalogName,
    ),
    matchReason: ProductMatchReason.lowConfidence,
  );

  test('constructs immutable product match candidates', () {
    expect(candidate.productId, 'product-1');
    expect(candidate.displayName, 'Milk');
    expect(candidate.matchingScore, 0.92);
    expect(candidate.confidence, 0.88);
    expect(candidate.matchReason, ProductMatchReason.normalizedMatch);
    expect(() => candidate.evidence.matchedTokens.add('other'),
        throwsUnsupportedError);
  });

  test('serializes and restores result and trace models', () {
    final result = ProductMatchResult(
      receiptLineId: 'line-1',
      matchedProduct: candidate,
      candidates: [candidate, rejectedCandidate],
      finalConfidence: 0.88,
      status: ProductMatchStatus.matched,
      decisionReason: ProductMatchReason.normalizedMatch,
      trace: ProductMatchTrace(
        evaluationOrder: const ['product-1', 'product-2'],
        candidateRanking: [candidate, rejectedCandidate],
        winningCandidate: candidate,
        rejectedCandidates: [rejectedCandidate],
        evidence: const {'source': 'receipt-line'},
        finalDecision: ProductMatchReason.normalizedMatch,
        normalizedQuery: 'milk',
        generatedCandidateCount: 2,
        generatedCandidateIds: const ['product-1', 'product-2'],
        generationOrder: const ['product-1', 'product-2'],
        discoveryEvidence: {
          'product-1': candidate.evidence,
          'product-2': rejectedCandidate.evidence,
        },
      ),
    );

    final json = result.toJson();
    final restored = ProductMatchResult.fromJson(json);

    expect(restored.toJson(), json);
    expect(restored.receiptLineId, 'line-1');
    expect(restored.matchedProduct?.productId, 'product-1');
    expect(restored.trace.winningCandidate?.productId, 'product-1');
    expect(restored.trace.rejectedCandidates.single.productId, 'product-2');
    expect(restored.trace.normalizedQuery, 'milk');
    expect(restored.trace.generatedCandidateCount, 2);
    expect(restored.trace.generatedCandidateIds, ['product-1', 'product-2']);
    expect(
        restored.trace.discoveryEvidence['product-1']!.matchedTokens, ['milk']);
    expect(() => restored.candidates.clear(), throwsUnsupportedError);
    expect(
        () => restored.trace.evaluationOrder.clear(), throwsUnsupportedError);
  });

  test('keeps reason and status enum values stable', () {
    expect(
      ProductMatchReason.values.map((value) => value.name),
      [
        'notEvaluated',
        'exactMatch',
        'normalizedMatch',
        'fuzzyMatch',
        'multipleCandidates',
        'lowConfidence',
        'noCandidate',
      ],
    );
    expect(
      ProductMatchStatus.values.map((value) => value.name),
      ['pending', 'matched', 'ambiguous', 'lowConfidence', 'noMatch'],
    );
  });
}
