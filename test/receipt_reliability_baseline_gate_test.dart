import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/orphan_line_recovery/application/orphan_line_recovery_service.dart';
import 'package:maqadi_v2/receipt_benchmark/application/receipt_benchmark_runner.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/application/receipt_extraction_benchmark_service.dart';
import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_input.dart';
import 'package:maqadi_v2/receipt_reliability_gate/application/receipt_reliability_gate.dart';
import 'package:maqadi_v2/receipt_reliability_gate/application/receipt_reliability_report_service.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_baselines.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_report.dart';
import 'package:maqadi_v2/receipt_reliability_gate/domain/receipt_reliability_snapshot.dart';

import 'receipt_benchmark_test_support.dart';

void main() {
  test('DAN-0001 receipt extraction does not regress from baseline', () async {
    const gate = ReceiptReliabilityGate();
    final definition = loadDan0001();
    final pipeline = await ReceiptBenchmarkRunner().run(definition);
    final recovery = await const OrphanLineRecoveryService().recover(
      elements: pipeline.actualUnderstanding.elements,
      lineResult: pipeline.actualLines,
    );
    final extraction = await const ReceiptExtractionBenchmarkService().analyze(
      ReceiptExtractionBenchmarkInput(
        receiptId: definition.receiptId,
        ocrResult: definition.toOcrResult(),
        understandingResult: pipeline.actualUnderstanding,
        lineResult: pipeline.actualLines,
      ),
    );
    final baseline = ReceiptReliabilitySnapshot.fromJson(
      jsonDecode(
        File('benchmark/DAN-0001/reliability-baseline.json').readAsStringSync(),
      ) as Map<String, Object?>,
    );
    final current = gate.capture(
      receiptId: definition.receiptId,
      extraction: extraction,
      recovery: recovery,
    );

    final result = gate.evaluate(baseline: baseline, current: current);

    expect(ReceiptReliabilityBaselines.dan0001.toJson(), baseline.toJson());
    expect(
      result.passed,
      isTrue,
      reason: result.toHumanReadableReport(),
    );

    final report = await const ReceiptReliabilityReportService().generate(
      input: ReceiptExtractionBenchmarkInput(
        receiptId: definition.receiptId,
        ocrResult: definition.toOcrResult(),
        understandingResult: pipeline.actualUnderstanding,
        lineResult: pipeline.actualLines,
      ),
      extraction: extraction,
    );
    expect(
      report.compatibility,
      ReceiptReliabilityBaselineCompatibility.comparable,
    );
    expect(report.benchmarkId, 'DAN-0001');
    expect(report.baselineId, 'DAN-0001');
    expect(report.passed, isTrue);
  });
}
