import '../../orphan_line_recovery/application/orphan_line_recovery_service.dart';
import '../../receipt_extraction_benchmark/domain/receipt_extraction_benchmark_input.dart';
import '../../receipt_extraction_benchmark/domain/receipt_extraction_benchmark_result.dart';
import '../domain/receipt_reliability_baselines.dart';
import '../domain/receipt_reliability_gate_result.dart';
import 'receipt_reliability_gate.dart';

class ReceiptReliabilityReportService {
  const ReceiptReliabilityReportService({
    ReceiptReliabilityGate gate = const ReceiptReliabilityGate(),
    OrphanLineRecoveryService recoveryService =
        const OrphanLineRecoveryService(),
  })  : _gate = gate,
        _recoveryService = recoveryService;

  final ReceiptReliabilityGate _gate;
  final OrphanLineRecoveryService _recoveryService;

  Future<ReceiptReliabilityGateResult> generate({
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
    return _gate.evaluate(
      baseline: ReceiptReliabilityBaselines.dan0001ForReceipt(input.receiptId),
      current: current,
    );
  }
}
