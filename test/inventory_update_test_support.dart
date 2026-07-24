import 'package:maqadi_v2/inventory_update/domain/inventory_update_models.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_decision.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_candidate.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_evidence.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_reason.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_result.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_trace.dart';

ProductMatchResult finalMatch({
  required String lineId,
  required String productId,
  required String displayName,
}) {
  final candidate = ProductMatchCandidate(
    productId: productId,
    displayName: displayName,
    matchingScore: 0.95,
    confidence: 0.9,
    evidence: ProductMatchEvidence(
      normalizedQuery: displayName,
      normalizedCatalogText: displayName,
      matchedTokens: [displayName],
      exactNormalizedMatch: true,
      discoverySource: ProductMatchDiscoverySource.catalogName,
      matchedCatalogText: displayName,
    ),
    matchReason: ProductMatchReason.exactMatch,
  );
  return ProductMatchResult(
    receiptLineId: lineId,
    matchedProduct: candidate,
    candidates: [candidate],
    finalConfidence: 0.9,
    status: ProductMatchStatus.matched,
    decisionReason: ProductMatchReason.clearWinner,
    decisionStatus: ProductDecisionStatus.matched,
    trace: ProductMatchTrace(
      evaluationOrder: [productId],
      candidateRanking: [candidate],
      winningCandidate: candidate,
      rejectedCandidates: const [],
      evidence: const {'selection': 'performed'},
      finalDecision: ProductMatchReason.clearWinner,
      decisionStatus: ProductDecisionStatus.matched,
    ),
  );
}

ProductMatchResult unknownMatch({required String lineId}) => ProductMatchResult(
      receiptLineId: lineId,
      matchedProduct: null,
      candidates: const [],
      finalConfidence: 0,
      status: ProductMatchStatus.noMatch,
      decisionReason: ProductMatchReason.noCandidates,
      decisionStatus: ProductDecisionStatus.noMatch,
      trace: ProductMatchTrace(
        evaluationOrder: const [],
        candidateRanking: const [],
        winningCandidate: null,
        rejectedCandidates: const [],
        evidence: const {'selection': 'performed'},
        finalDecision: ProductMatchReason.noCandidates,
        decisionStatus: ProductDecisionStatus.noMatch,
      ),
    );

InventoryUpdateInput updateInput(
  List<MatchedReceiptProduct> products, {
  String receiptId = 'receipt-1',
}) =>
    InventoryUpdateInput(
      receiptId: receiptId,
      receivedAt: DateTime.utc(2026, 7, 24),
      products: products,
    );

MatchedReceiptProduct receiptProduct(
  ProductMatchResult result, {
  double quantity = 1,
}) =>
    MatchedReceiptProduct(matchResult: result, quantity: quantity);
