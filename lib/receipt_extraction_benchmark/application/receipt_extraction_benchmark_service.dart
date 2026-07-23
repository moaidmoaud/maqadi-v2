import '../../orphan_line_diagnostics/application/orphan_line_diagnostics_service.dart';
import '../../orphan_line_diagnostics/domain/orphan_line_diagnostic.dart';
import '../../receipt_line_builder/domain/receipt_line.dart';
import '../../receipt_line_builder/domain/receipt_line_completeness.dart';
import '../../receipt_understanding/domain/receipt_element.dart';
import '../../receipt_understanding/domain/receipt_element_type.dart';
import '../domain/receipt_extraction_benchmark_input.dart';
import '../domain/receipt_extraction_benchmark_result.dart';

class ReceiptExtractionBenchmarkService {
  const ReceiptExtractionBenchmarkService({
    OrphanLineDiagnosticsService orphanDiagnosticsService =
        const OrphanLineDiagnosticsService(),
  }) : _orphanDiagnosticsService = orphanDiagnosticsService;

  final OrphanLineDiagnosticsService _orphanDiagnosticsService;

  Future<ReceiptExtractionBenchmarkResult> analyze(
    ReceiptExtractionBenchmarkInput input,
  ) async {
    final elementsById = {
      for (final element in input.understandingResult.elements)
        element.id: element,
    };
    final missingLines = <ReceiptExtractionMissingLine>[];
    final productTexts = <String>[];
    var recoverableProductLines = 0;
    var emptyProductTextCount = 0;

    for (final line in input.lineResult.lines) {
      final productElement = _productElement(line, elementsById);
      final productText = productElement?.text.trim() ?? '';
      final recoverable = _isRecoverableProductLine(line, productElement);
      if (recoverable) recoverableProductLines++;
      if (productText.isNotEmpty &&
          productElement?.type == ReceiptElementType.productName) {
        productTexts.add(_normalizeForDuplicateDetection(productText));
        continue;
      }
      if (productElement != null && productText.isEmpty) {
        emptyProductTextCount++;
      }
      missingLines.add(
        ReceiptExtractionMissingLine(
          lineId: line.id,
          elementIds: line.referencedElementIds,
          reason: _missingReason(
            input: input,
            line: line,
            productElement: productElement,
            elementsById: elementsById,
          ),
          summary: _missingSummary(line, productElement),
        ),
      );
    }

    final duplicateProductTextCount = _duplicateCount(productTexts);
    final linesContainingProductText = productTexts.length;
    final receiptLineCount = input.lineResult.lines.length;
    final orphanDiagnostics = await _orphanDiagnosticsService.diagnose(
      elements: input.understandingResult.elements,
      lineResult: input.lineResult,
    );
    final metrics = ReceiptExtractionMetrics(
      ocrTextBlocks: input.ocrResult.blocks.length,
      receiptElements: input.understandingResult.elements.length,
      receiptLines: receiptLineCount,
      linesContainingProductText: linesContainingProductText,
      linesWithoutProductText: receiptLineCount - linesContainingProductText,
      recoverableProductLines: recoverableProductLines,
      productTextCoverage: _ratio(
        linesContainingProductText,
        recoverableProductLines,
      ),
      recoverableProductLinesPercentage: _ratio(
        recoverableProductLines,
        receiptLineCount,
      ),
      duplicateProductTextCount: duplicateProductTextCount,
      emptyProductTextCount: emptyProductTextCount,
    );
    return ReceiptExtractionBenchmarkResult(
      receiptId: input.receiptId,
      storeName: _storeName(input.understandingResult.elements),
      metrics: metrics,
      missingLines: missingLines,
      failureBreakdown: _failureBreakdown(missingLines),
      orphanRecoverySummary:
          OrphanRecoverySummary.fromDiagnostics(orphanDiagnostics),
    );
  }

  ReceiptElement? _productElement(
    ReceiptLine line,
    Map<String, ReceiptElement> elementsById,
  ) {
    final id = line.productElementId;
    return id == null ? null : elementsById[id];
  }

  bool _isRecoverableProductLine(
    ReceiptLine line,
    ReceiptElement? productElement,
  ) =>
      productElement?.type == ReceiptElementType.productName ||
      line.priceElementId != null ||
      line.quantityElementId != null ||
      line.lineTotalElementId != null;

  ReceiptExtractionMissingReason _missingReason({
    required ReceiptExtractionBenchmarkInput input,
    required ReceiptLine line,
    required ReceiptElement? productElement,
    required Map<String, ReceiptElement> elementsById,
  }) {
    final hasOcrText =
        input.ocrResult.blocks.any((block) => block.text.trim().isNotEmpty);
    if (!hasOcrText) return ReceiptExtractionMissingReason.missingOcrText;

    final referenced = line.referencedElementIds
        .map((elementId) => elementsById[elementId])
        .whereType<ReceiptElement>()
        .toList(growable: false);
    if (referenced.isNotEmpty &&
        referenced.every((element) =>
            element.type == ReceiptElementType.header ||
            element.type == ReceiptElementType.storeName)) {
      return ReceiptExtractionMissingReason.headerOnly;
    }
    if (referenced.isNotEmpty &&
        referenced.every((element) =>
            element.type == ReceiptElementType.footer ||
            element.type == ReceiptElementType.metadata)) {
      return ReceiptExtractionMissingReason.footerOnly;
    }
    if (line.completeness == ReceiptLineCompleteness.orphan) {
      return ReceiptExtractionMissingReason.orphanLine;
    }
    if (line.productElementId != null &&
        (productElement == null ||
            productElement.type != ReceiptElementType.productName ||
            productElement.text.trim().isEmpty)) {
      return ReceiptExtractionMissingReason.unresolvedProductText;
    }
    return ReceiptExtractionMissingReason.unknown;
  }

  String _missingSummary(
    ReceiptLine line,
    ReceiptElement? productElement,
  ) {
    if (line.completeness == ReceiptLineCompleteness.orphan) {
      return 'The structural line has no product anchor.';
    }
    if (line.productElementId != null && productElement == null) {
      return 'The product element reference could not be resolved.';
    }
    if (productElement != null && productElement.text.trim().isEmpty) {
      return 'The product element contains no usable text.';
    }
    return 'No usable product text reached this receipt line.';
  }

  String? _storeName(Iterable<ReceiptElement> elements) {
    for (final element in elements) {
      if (element.type == ReceiptElementType.storeName &&
          element.text.trim().isNotEmpty) {
        return element.text.trim();
      }
    }
    return null;
  }

  String _normalizeForDuplicateDetection(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  int _duplicateCount(Iterable<String> values) {
    final seen = <String>{};
    var duplicates = 0;
    for (final value in values) {
      if (!seen.add(value)) duplicates++;
    }
    return duplicates;
  }

  Map<ReceiptExtractionMissingReason, int> _failureBreakdown(
    Iterable<ReceiptExtractionMissingLine> lines,
  ) {
    final result = <ReceiptExtractionMissingReason, int>{};
    for (final line in lines) {
      result[line.reason] = (result[line.reason] ?? 0) + 1;
    }
    return result;
  }

  double _ratio(int numerator, int denominator) =>
      denominator == 0 ? 0 : numerator / denominator;
}
