import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching_v2/application/product_matching_service_v2.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_reason.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_result.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  const service = PlaceholderProductMatchingServiceV2();

  test('placeholder service accepts a receipt line and returns pending result',
      () async {
    final line =
        const ReceiptLineBuilderEngine().build(productRow()).lines.single;

    final result = await service.match(line);

    expect(result.receiptLineId, line.id);
    expect(result.matchedProduct, isNull);
    expect(result.candidates, isEmpty);
    expect(result.finalConfidence, isNull);
    expect(result.status, ProductMatchStatus.pending);
    expect(result.decisionReason, ProductMatchReason.notEvaluated);
    expect(result.trace.evaluationOrder, isEmpty);
    expect(result.trace.candidateRanking, isEmpty);
    expect(result.trace.winningCandidate, isNull);
    expect(result.trace.rejectedCandidates, isEmpty);
    expect(result.trace.finalDecision, ProductMatchReason.notEvaluated);
  });

  test('placeholder service is deterministic for the same receipt line',
      () async {
    final line =
        const ReceiptLineBuilderEngine().build(productRow()).lines.single;

    final first = await service.match(line);
    final second = await service.match(line);

    expect(first.toJson(), second.toJson());
  });
}
