import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/application/receipt_extraction_benchmark_service.dart';
import 'package:maqadi_v2/receipt_reliability_gate/application/receipt_reliability_report_service.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_baselines.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_report.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_snapshot.dart';

import 'receipt_extraction_benchmark_test_support.dart';

void main() {
  test('arbitrary runtime receipt has no persisted compatible baseline',
      () async {
    final input = extractionInput(receiptId: 'runtime-receipt');
    final extraction =
        await const ReceiptExtractionBenchmarkService().analyze(input);

    final report = await const ReceiptReliabilityReportService().generate(
      input: input,
      extraction: extraction,
    );

    expect(
      report.compatibility,
      ReceiptReliabilityBaselineCompatibility.missingBaseline,
    );
    expect(report.benchmarkId, 'runtime-receipt');
    expect(report.baselineId, isNull);
    expect(report.gateResult, isNull);
    expect(report.passed, isNull);
    expect(report.toHumanReadableReport(), isNot(contains('PASS')));
    expect(report.toHumanReadableReport(), isNot(contains('FAIL')));
  });

  test('explicit baseline for another receipt is incompatible', () async {
    final input = extractionInput(receiptId: 'runtime-receipt');
    final extraction =
        await const ReceiptExtractionBenchmarkService().analyze(input);
    const service = ReceiptReliabilityReportService(
      baselineOverride: ReceiptReliabilityBaselines.dan0001,
    );

    final report = await service.generate(
      input: input,
      extraction: extraction,
    );

    expect(
      report.compatibility,
      ReceiptReliabilityBaselineCompatibility.incompatibleBaseline,
    );
    expect(report.benchmarkId, 'runtime-receipt');
    expect(report.baselineId, 'DAN-0001');
    expect(report.gateResult, isNull);
    expect(report.passed, isNull);
  });

  test('baseline registry resolves only the exact DAN-0001 identity', () {
    expect(
      ReceiptReliabilityBaselines.forBenchmark('DAN-0001'),
      same(ReceiptReliabilityBaselines.dan0001),
    );
    expect(
      ReceiptReliabilityBaselines.forBenchmark('runtime-DAN-0001'),
      isNull,
    );
  });

  test('compatibility report serialization preserves typed state', () {
    const current = ReceiptReliabilityBaselines.dan0001;
    final report = ReceiptReliabilityReport.incompatibleBaseline(
      current: const ReceiptReliabilitySnapshot(
        receiptId: 'runtime-receipt',
        productTextCoverage: 0.7,
        recoveredOrphans: 4,
        remainingOrphans: 3,
        completeLines: 7,
        partialLines: 2,
        orphanLines: 3,
      ),
      baseline: current,
    );

    final restored = ReceiptReliabilityReport.fromJson(report.toJson());

    expect(restored.compatibility, report.compatibility);
    expect(restored.benchmarkId, report.benchmarkId);
    expect(restored.baselineId, report.baselineId);
    expect(restored.gateResult, isNull);
  });
}
