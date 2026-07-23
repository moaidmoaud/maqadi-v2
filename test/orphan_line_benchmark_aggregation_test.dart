import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/orphan_line_diagnostics/application/orphan_line_diagnostics_service.dart';
import 'package:maqadi_v2/orphan_line_diagnostics/domain/orphan_line_diagnostic.dart';
import 'package:maqadi_v2/receipt_benchmark/application/receipt_benchmark_runner.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/application/receipt_extraction_benchmark_service.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_result.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';

import 'orphan_line_diagnostics_test_support.dart';
import 'receipt_benchmark_test_support.dart';
import 'receipt_extraction_benchmark_test_support.dart';

void main() {
  test('extraction benchmark aggregates orphan recovery diagnostics', () async {
    final diagnostics = [
      orphanDiagnostic(
        id: 'yes',
        recovery: OrphanRecoveryPossibility.yes,
      ),
      orphanDiagnostic(
        id: 'maybe',
        recovery: OrphanRecoveryPossibility.maybe,
      ),
      orphanDiagnostic(
        id: 'no',
        recovery: OrphanRecoveryPossibility.no,
      ),
    ];
    final service = ReceiptExtractionBenchmarkService(
      orphanDiagnosticsService: _StubOrphanService(diagnostics),
    );

    final result = await service.analyze(extractionInput());

    expect(result.orphanRecoverySummary.recoverable, 1);
    expect(result.orphanRecoverySummary.maybeRecoverable, 1);
    expect(result.orphanRecoverySummary.unrecoverable, 1);
    expect(result.metrics.receiptLines, 0);

    final legacyJson = Map<String, Object?>.from(result.toJson())
      ..remove('orphanRecoverySummary');
    final restored = ReceiptExtractionBenchmarkResult.fromJson(legacyJson);
    expect(restored.orphanRecoverySummary.total, 0);
  });

  test('DAN-0001 proxy orphan summary matches the unchanged line output',
      () async {
    final baseline = await ReceiptBenchmarkRunner().run(loadDan0001());
    final diagnostics = await const OrphanLineDiagnosticsService().diagnose(
      elements: baseline.actualUnderstanding.elements,
      lineResult: baseline.actualLines,
    );
    final summary = OrphanRecoverySummary.fromDiagnostics(diagnostics);
    final orphanCount = baseline.actualLines.lines
        .where((line) => line.completeness == ReceiptLineCompleteness.orphan)
        .length;

    expect(summary.total, orphanCount);
    expect(summary.recoverable, 0);
    expect(summary.maybeRecoverable, 1);
    expect(summary.unrecoverable, 0);
    expect(
      diagnostics.single.rejectionReason,
      OrphanLineReason.failedRowGrouping,
    );
  });
}

class _StubOrphanService extends OrphanLineDiagnosticsService {
  _StubOrphanService(this.diagnostics);

  final List<OrphanLineDiagnostic> diagnostics;

  @override
  Future<List<OrphanLineDiagnostic>> diagnose({
    required List<ReceiptElement> elements,
    required ReceiptLineResult lineResult,
  }) async =>
      diagnostics;
}
