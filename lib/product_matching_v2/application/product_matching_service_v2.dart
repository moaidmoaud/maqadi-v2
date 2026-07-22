import '../../receipt_line_builder/domain/receipt_line.dart';
import '../domain/product_match_reason.dart';
import '../domain/product_match_result.dart';
import '../domain/product_match_trace.dart';

abstract interface class ProductMatchingServiceV2 {
  Future<ProductMatchResult> match(ReceiptLine line);
}

class PlaceholderProductMatchingServiceV2 implements ProductMatchingServiceV2 {
  const PlaceholderProductMatchingServiceV2();

  @override
  Future<ProductMatchResult> match(ReceiptLine line) async =>
      ProductMatchResult(
        receiptLineId: line.id,
        matchedProduct: null,
        candidates: const [],
        finalConfidence: null,
        status: ProductMatchStatus.pending,
        decisionReason: ProductMatchReason.notEvaluated,
        trace: ProductMatchTrace(
          evaluationOrder: const [],
          candidateRanking: const [],
          winningCandidate: null,
          rejectedCandidates: const [],
          evidence: const {
            'foundation': 'Matching algorithm intentionally not implemented.',
          },
          finalDecision: ProductMatchReason.notEvaluated,
        ),
      );
}
