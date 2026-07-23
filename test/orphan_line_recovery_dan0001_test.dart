import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/orphan_line_recovery/application/orphan_line_recovery_service.dart';
import 'package:maqadi_v2/receipt_benchmark/application/receipt_benchmark_runner.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';

import 'receipt_benchmark_test_support.dart';

void main() {
  test('DAN-0001 builder baseline is preserved before recovery', () async {
    final baseline = await ReceiptBenchmarkRunner().run(loadDan0001());
    final beforeOrphans = baseline.actualLines.lines
        .where((line) => line.completeness == ReceiptLineCompleteness.orphan)
        .length;

    final recovery = await const OrphanLineRecoveryService().recover(
      elements: baseline.actualUnderstanding.elements,
      lineResult: baseline.actualLines,
    );

    expect(beforeOrphans, 1);
    expect(recovery.recoveredOrphanCount, 0);
    expect(recovery.remainingOrphanCount, 1);
    expect(recovery.lines, hasLength(3));
    expect(recovery.lines, baseline.actualLines.lines);
  });
}
