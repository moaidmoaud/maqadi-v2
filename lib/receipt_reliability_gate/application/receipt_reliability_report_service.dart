import '../../orphan_line_recovery/application/orphan_line_recovery_service.dart';
import '../../receipt_extraction_benchmark/domain/receipt_extraction_benchmark_input.dart';
import '../../receipt_extraction_benchmark/domain/receipt_extraction_benchmark_result.dart';
import '../domain/receipt_reliability_baselines.dart';
import '../domain/receipt_reliability_report.dart';
import '../domain/receipt_reliability_snapshot.dart';
import 'receipt_reliability_gate.dart';

class ReceiptReliabilityReportService {
  const ReceiptReliabilityReportService({
    ReceiptReliabilityGate gate = const ReceiptReliabilityGate(),
    OrphanLineRecoveryService recoveryService =
        const OrphanLineRecoveryService(),
    ReceiptReliabilitySnapshot? baselineOverride,
  })  : _gate = gate,
        _recoveryService = recoveryService,
        _baselineOverride = baselineOverride;

  final ReceiptReliabilityGate _gate;
  final OrphanLineRecoveryService _recoveryService;
  final ReceiptReliabilitySnapshot? _baselineOverride;

  Future<ReceiptReliabilityReport> generate({
    required ReceiptExtractionBenchmarkInput input,
    required ReceiptExtractionBenchmarkResult extraction,
  }) async {
    final recovery = await _recoveryService.recover(
      elements: input.understandingResult.elements,
      lineResult: input.lineResult,
    );
    final current = _gate.capture(
      receiptId: input.receiptId,
      extraction: extraction,
      recovery: recovery,
    );
    final baseline = _baselineOverride ??
        ReceiptReliabilityBaselines.forBenchmark(input.receiptId);
    if (baseline == null) {
      return ReceiptReliabilityReport.missingBaseline(current: current);
    }
    if (baseline.receiptId != current.receiptId) {
      return ReceiptReliabilityReport.incompatibleBaseline(
        current: current,
        baseline: baseline,
      );
    }
    return ReceiptReliabilityReport.comparable(
      gateResult: _gate.evaluate(baseline: baseline, current: current),
    );
  }
}
