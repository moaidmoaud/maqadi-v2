import 'package:maqadi_v2/receipt_extraction_benchmark/domain/receipt_extraction_benchmark_input.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_evidence.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_understanding_result.dart';

import 'receipt_line_builder_test_support.dart';

ReceiptExtractionBenchmarkInput extractionInput({
  String receiptId = 'receipt-1',
  List<ReceiptElement> elements = const [],
  List<ReceiptLine> lines = const [],
  List<String> ocrTexts = const ['receipt text'],
}) =>
    ReceiptExtractionBenchmarkInput(
      receiptId: receiptId,
      ocrResult: ReceiptOcrResult(
        text: ocrTexts.join('\n'),
        blocks: [
          for (final text in ocrTexts)
            ReceiptOcrBlock(text: text, lines: const []),
        ],
      ),
      understandingResult: ReceiptUnderstandingResult(
        elements: elements,
        ocrOrderPreserved: true,
      ),
      lineResult: ReceiptLineResult(
        lines: lines,
        unassignedElements: const [],
        failures: const [],
      ),
    );

ReceiptLine extractionLine({
  required String id,
  String? productId,
  String? priceId,
  String? quantityId,
  String? discountId,
  String? taxId,
  String? lineTotalId,
  ReceiptLineCompleteness completeness = ReceiptLineCompleteness.partial,
}) =>
    ReceiptLine(
      id: id,
      productElementId: productId,
      priceElementId: priceId,
      quantityElementId: quantityId,
      discountElementId: discountId,
      taxElementId: taxId,
      lineTotalElementId: lineTotalId,
      completeness: completeness,
      evidence: ReceiptLineEvidence(
        anchorElementId: productId,
        attachedElementIds: [
          priceId,
          quantityId,
          discountId,
          taxId,
          lineTotalId,
        ].whereType<String>(),
        normalizedVerticalDistances: const {},
        normalizedHorizontalDistances: const {},
        overlapMetrics: const {},
        columnEvidence: const {},
        appliedGroupingRule: 'test',
        rejectedCandidates: const {},
        confidenceFactors: const [],
        summary: 'test',
      ),
    );

List<ReceiptElement> fullCoverageElements() => [
      receiptElement(
        'store',
        ReceiptElementType.storeName,
        text: 'Tamimi',
      ),
      receiptElement(
        'garlic',
        ReceiptElementType.productName,
        text: 'Garlic Bag',
      ),
      receiptElement(
        'potatoes',
        ReceiptElementType.productName,
        text: 'Potatoes Bag',
      ),
    ];
