import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/orphan_line_recovery/application/orphan_line_recovery_service.dart';
import 'package:maqadi_v2/orphan_line_recovery/domain/orphan_line_recovery_result.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';

import 'orphan_line_recovery_test_support.dart';

void main() {
  const service = OrphanLineRecoveryService();

  test('recovers a same-row price orphan into a complete line', () async {
    final fixture = sameRowPriceFixture();

    final result = await service.recover(
      elements: fixture.elements,
      lineResult: fixture.lineResult,
    );

    expect(result.lines, hasLength(1));
    expect(result.lines.single.completeness, ReceiptLineCompleteness.complete);
    expect(result.lines.single.productElementId, 'product');
    expect(result.lines.single.priceElementId, 'price');
    expect(result.recoveredOrphanCount, 1);
    expect(result.remainingOrphanCount, 0);
    expect(
      result.attempts.single.outcome,
      OrphanRecoveryOutcome.recoveredComplete,
    );
    expect(
      result.attempts.single.decisionReason,
      OrphanRecoveryDecisionReason.recoveredUniqueSameRow,
    );
    expect(
      result.attempts.single.confidence,
      OrphanRecoveryConfidence.high,
    );
  });

  test('recovers a same-row quantity orphan as a partial line', () async {
    final fixture = sameRowQuantityFixture();

    final result = await service.recover(
      elements: fixture.elements,
      lineResult: fixture.lineResult,
    );

    expect(result.lines, hasLength(1));
    expect(result.lines.single.completeness, ReceiptLineCompleteness.partial);
    expect(result.lines.single.quantityElementId, 'quantity');
    expect(
      result.attempts.single.outcome,
      OrphanRecoveryOutcome.recoveredPartial,
    );
  });

  test('recovers a unique same-column role with moderate confidence', () async {
    final fixture = sameColumnQuantityFixture();

    final result = await service.recover(
      elements: fixture.elements,
      lineResult: fixture.lineResult,
    );

    expect(result.lines, hasLength(1));
    expect(result.lines.single.quantityElementId, 'quantity');
    expect(
      result.attempts.single.decisionReason,
      OrphanRecoveryDecisionReason.recoveredUniqueSameColumn,
    );
    expect(
      result.attempts.single.confidence,
      OrphanRecoveryConfidence.moderate,
    );
  });

  test('keeps an orphan explicit when no product candidate exists', () async {
    final fixture = priceOnlyFixture();

    final result = await service.recover(
      elements: fixture.elements,
      lineResult: fixture.lineResult,
    );

    expect(result.recoveredOrphanCount, 0);
    expect(result.remainingOrphanCount, 1);
    expect(result.lines.single.completeness, ReceiptLineCompleteness.orphan);
    expect(
      result.attempts.single.outcome,
      OrphanRecoveryOutcome.unrecoverable,
    );
    expect(
      result.attempts.single.decisionReason,
      OrphanRecoveryDecisionReason.noProductCandidate,
    );
  });

  test('does not choose among multiple orphans competing for one role',
      () async {
    final fixture = competingPriceFixture();

    final result = await service.recover(
      elements: fixture.elements,
      lineResult: fixture.lineResult,
    );

    expect(result.recoveredOrphanCount, 0);
    expect(result.remainingOrphanCount, 2);
    expect(result.attempts, hasLength(2));
    expect(
      result.attempts.map((attempt) => attempt.decisionReason),
      everyElement(OrphanRecoveryDecisionReason.competingOrphans),
    );
  });

  test('does not choose among multiple compatible product lines', () async {
    final fixture = ambiguousProductFixture();

    final result = await service.recover(
      elements: fixture.elements,
      lineResult: fixture.lineResult,
    );

    expect(result.recoveredOrphanCount, 0);
    expect(result.remainingOrphanCount, 1);
    expect(
      result.attempts.single.decisionReason,
      OrphanRecoveryDecisionReason.multipleProductCandidates,
    );
  });

  test('recovery attempt trace has stable serialization', () async {
    final fixture = sameRowPriceFixture();
    final result = await service.recover(
      elements: fixture.elements,
      lineResult: fixture.lineResult,
    );
    final attempt = result.attempts.single;

    final restored = OrphanRecoveryAttempt.fromJson(attempt.toJson());

    expect(restored.toJson(), attempt.toJson());
    expect(restored.rule, OrphanRecoveryRule.sameRowNearestProduct);
    expect(restored.recoveredCompleteness, ReceiptLineCompleteness.complete);
  });

  test('repeated recovery is deterministic', () async {
    final fixture = sameRowPriceFixture();

    final first = await service.recover(
      elements: fixture.elements,
      lineResult: fixture.lineResult,
    );
    final second = await service.recover(
      elements: fixture.elements,
      lineResult: fixture.lineResult,
    );

    expect(
      second.attempts.map((attempt) => attempt.toJson()),
      first.attempts.map((attempt) => attempt.toJson()),
    );
    expect(
      second.lines.map((line) => line.referencedElementIds),
      first.lines.map((line) => line.referencedElementIds),
    );
  });
}
