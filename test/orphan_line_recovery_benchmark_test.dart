import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/application/receipt_extraction_benchmark_service.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_input.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_result.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_understanding_result.dart';

import 'orphan_line_recovery_test_support.dart';

void main() {
  test('benchmark compares coverage before and after recovery', () async {
    final fixture = sameRowPriceFixture();
    final input = ReceiptExtractionBenchmarkInput(
      receiptId: 'recovery-receipt',
      ocrResult: const ReceiptOcrResult(
        text: 'Garlic Bag 10.00',
        blocks: [ReceiptOcrBlock(text: 'Garlic Bag 10.00', lines: [])],
      ),
      understandingResult: ReceiptUnderstandingResult(
        elements: fixture.elements,
        ocrOrderPreserved: true,
      ),
      lineResult: fixture.lineResult,
    );

    final result =
        await const ReceiptExtractionBenchmarkService().analyze(input);

    expect(result.recoveryComparison.beforeRecoveryCoverage, 0.5);
    expect(result.recoveryComparison.afterRecoveryCoverage, 1);
    expect(result.recoveryComparison.coverageImprovement, 0.5);
    expect(result.recoveryComparison.recoveredOrphans, 1);
    expect(result.recoveryComparison.remainingOrphans, 0);
    expect(result.metrics.productTextCoverage, 0.5);

    final restored = ReceiptExtractionBenchmarkResult.fromJson(result.toJson());
    expect(restored.recoveryComparison.toJson(),
        result.recoveryComparison.toJson());
  });

  test('legacy benchmark JSON defaults to an empty recovery comparison',
      () async {
    final fixture = priceOnlyFixture();
    final input = ReceiptExtractionBenchmarkInput(
      receiptId: 'legacy-receipt',
      ocrResult: const ReceiptOcrResult(
        text: '10.00',
        blocks: [ReceiptOcrBlock(text: '10.00', lines: [])],
      ),
      understandingResult: ReceiptUnderstandingResult(
        elements: fixture.elements,
        ocrOrderPreserved: true,
      ),
      lineResult: fixture.lineResult,
    );
    final result =
        await const ReceiptExtractionBenchmarkService().analyze(input);
    final legacy = Map<String, Object?>.from(result.toJson())
      ..remove('recoveryComparison');

    final restored = ReceiptExtractionBenchmarkResult.fromJson(legacy);

    expect(restored.recoveryComparison.recoveredOrphans, 0);
    expect(restored.recoveryComparison.coverageImprovement, 0);
  });
}
