import '../../orphan_line_diagnostics/domain/orphan_line_diagnostic.dart';

enum ReceiptExtractionMissingReason {
  missingOcrText,
  headerOnly,
  footerOnly,
  orphanLine,
  unresolvedProductText,
  unknown,
}

class ReceiptExtractionMissingLine {
  ReceiptExtractionMissingLine({
    required this.lineId,
    required Iterable<String> elementIds,
    required this.reason,
    required this.summary,
  }) : elementIds = List.unmodifiable(elementIds);

  factory ReceiptExtractionMissingLine.fromJson(Map<String, Object?> json) =>
      ReceiptExtractionMissingLine(
        lineId: json['lineId']! as String,
        elementIds: (json['elementIds']! as List<Object?>).cast(),
        reason: ReceiptExtractionMissingReason.values.byName(
          json['reason']! as String,
        ),
        summary: json['summary']! as String,
      );

  final String lineId;
  final List<String> elementIds;
  final ReceiptExtractionMissingReason reason;
  final String summary;

  Map<String, Object?> toJson() => {
        'lineId': lineId,
        'elementIds': elementIds,
        'reason': reason.name,
        'summary': summary,
      };
}

class ReceiptExtractionMetrics {
  const ReceiptExtractionMetrics({
    required this.ocrTextBlocks,
    required this.receiptElements,
    required this.receiptLines,
    required this.linesContainingProductText,
    required this.linesWithoutProductText,
    required this.recoverableProductLines,
    required this.productTextCoverage,
    required this.recoverableProductLinesPercentage,
    required this.duplicateProductTextCount,
    required this.emptyProductTextCount,
  });

  factory ReceiptExtractionMetrics.fromJson(Map<String, Object?> json) =>
      ReceiptExtractionMetrics(
        ocrTextBlocks: json['ocrTextBlocks']! as int,
        receiptElements: json['receiptElements']! as int,
        receiptLines: json['receiptLines']! as int,
        linesContainingProductText: json['linesContainingProductText']! as int,
        linesWithoutProductText: json['linesWithoutProductText']! as int,
        recoverableProductLines: json['recoverableProductLines']! as int,
        productTextCoverage: (json['productTextCoverage']! as num).toDouble(),
        recoverableProductLinesPercentage:
            (json['recoverableProductLinesPercentage']! as num).toDouble(),
        duplicateProductTextCount: json['duplicateProductTextCount']! as int,
        emptyProductTextCount: json['emptyProductTextCount']! as int,
      );

  final int ocrTextBlocks;
  final int receiptElements;
  final int receiptLines;
  final int linesContainingProductText;
  final int linesWithoutProductText;
  final int recoverableProductLines;
  final double productTextCoverage;
  final double recoverableProductLinesPercentage;
  final int duplicateProductTextCount;
  final int emptyProductTextCount;

  Map<String, Object?> toJson() => {
        'ocrTextBlocks': ocrTextBlocks,
        'receiptElements': receiptElements,
        'receiptLines': receiptLines,
        'linesContainingProductText': linesContainingProductText,
        'linesWithoutProductText': linesWithoutProductText,
        'recoverableProductLines': recoverableProductLines,
        'productTextCoverage': productTextCoverage,
        'recoverableProductLinesPercentage': recoverableProductLinesPercentage,
        'duplicateProductTextCount': duplicateProductTextCount,
        'emptyProductTextCount': emptyProductTextCount,
      };
}

class ReceiptExtractionBenchmarkResult {
  ReceiptExtractionBenchmarkResult({
    required this.receiptId,
    required this.storeName,
    required this.metrics,
    required Iterable<ReceiptExtractionMissingLine> missingLines,
    required Map<ReceiptExtractionMissingReason, int> failureBreakdown,
    this.orphanRecoverySummary = const OrphanRecoverySummary.empty(),
  })  : missingLines = List.unmodifiable(missingLines),
        failureBreakdown = Map.unmodifiable(failureBreakdown);

  factory ReceiptExtractionBenchmarkResult.fromJson(
    Map<String, Object?> json,
  ) =>
      ReceiptExtractionBenchmarkResult(
        receiptId: json['receiptId']! as String,
        storeName: json['storeName'] as String?,
        metrics: ReceiptExtractionMetrics.fromJson(
          json['metrics']! as Map<String, Object?>,
        ),
        missingLines: (json['missingLines']! as List<Object?>).map(
          (value) => ReceiptExtractionMissingLine.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
        failureBreakdown:
            (json['failureBreakdown']! as Map<Object?, Object?>).map(
          (key, value) => MapEntry(
            ReceiptExtractionMissingReason.values.byName(key! as String),
            value! as int,
          ),
        ),
        orphanRecoverySummary: json['orphanRecoverySummary'] == null
            ? const OrphanRecoverySummary.empty()
            : OrphanRecoverySummary.fromJson(
                json['orphanRecoverySummary']! as Map<String, Object?>,
              ),
      );

  final String receiptId;
  final String? storeName;
  final ReceiptExtractionMetrics metrics;
  final List<ReceiptExtractionMissingLine> missingLines;
  final Map<ReceiptExtractionMissingReason, int> failureBreakdown;
  final OrphanRecoverySummary orphanRecoverySummary;

  Map<String, Object?> toJson() => {
        'receiptId': receiptId,
        'storeName': storeName,
        'metrics': metrics.toJson(),
        'missingLines': [for (final line in missingLines) line.toJson()],
        'failureBreakdown': {
          for (final entry in failureBreakdown.entries)
            entry.key.name: entry.value,
        },
        'orphanRecoverySummary': orphanRecoverySummary.toJson(),
      };
}
