import 'dart:convert';
import 'dart:io';

import 'package:maqadi_v2/receipt_benchmark/domain/receipt_benchmark_definition.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_evidence.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/unassigned_receipt_element.dart';

ReceiptBenchmarkDefinition loadDan0001() => ReceiptBenchmarkDefinition.fromJson(
      jsonDecode(File('benchmark/DAN-0001/benchmark.json').readAsStringSync())
          as Map<String, Object?>,
    );

ReceiptLine benchmarkLine({
  required String id,
  String? product,
  String? quantity,
  String? price,
  String? lineTotal,
  String? discount,
  String? tax,
  ReceiptLineCompleteness? completeness,
}) {
  final state = completeness ??
      (product == null
          ? ReceiptLineCompleteness.orphan
          : price == null
              ? ReceiptLineCompleteness.partial
              : ReceiptLineCompleteness.complete);
  final references = [product, quantity, price, lineTotal, discount, tax]
      .whereType<String>()
      .toList();
  return ReceiptLine(
    id: id,
    productElementId: product,
    quantityElementId: quantity,
    priceElementId: price,
    lineTotalElementId: lineTotal,
    discountElementId: discount,
    taxElementId: tax,
    completeness: state,
    evidence: ReceiptLineEvidence(
      anchorElementId: product,
      attachedElementIds: references,
      normalizedVerticalDistances: const {},
      normalizedHorizontalDistances: const {},
      overlapMetrics: const {},
      columnEvidence: const {},
      appliedGroupingRule: 'benchmark-test',
      rejectedCandidates: const {},
      confidenceFactors: const [],
      summary: 'benchmark test',
    ),
  );
}

ReceiptLineResult benchmarkLineResult(
  List<ReceiptLine> lines, {
  List<UnassignedReceiptElement> unassigned = const [],
}) =>
    ReceiptLineResult(
      lines: lines,
      unassignedElements: unassigned,
      failures: const [],
    );

UnassignedReceiptElement benchmarkUnassigned(String id) =>
    UnassignedReceiptElement(
      elementId: id,
      reasonCode: UnassignedReceiptElementReason.excludedElementType,
      evidence: ReceiptLineEvidence(
        anchorElementId: null,
        attachedElementIds: [id],
        normalizedVerticalDistances: const {},
        normalizedHorizontalDistances: const {},
        overlapMetrics: const {},
        columnEvidence: const {},
        appliedGroupingRule: 'benchmark-test-unassigned',
        rejectedCandidates: const {},
        confidenceFactors: const [],
        summary: 'benchmark test',
      ),
    );
