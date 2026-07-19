import 'dart:typed_data';

enum PdfReportType {
  currentInventory,
  shoppingList,
  expiringSoon,
  expired,
  lowStock,
  dashboardSummary,
}

enum CsvReportType { inventory, shoppingList }

class ReportFilter {
  const ReportFilter({
    this.category,
    this.lowStock = false,
    this.outOfStock = false,
    this.expiringSoon = false,
    this.expired = false,
  });

  final String? category;
  final bool lowStock;
  final bool outOfStock;
  final bool expiringSoon;
  final bool expired;

  bool get hasStatusFilter => lowStock || outOfStock || expiringSoon || expired;

  ReportFilter copyWith({
    String? category,
    bool clearCategory = false,
    bool? lowStock,
    bool? outOfStock,
    bool? expiringSoon,
    bool? expired,
  }) =>
      ReportFilter(
        category: clearCategory ? null : category ?? this.category,
        lowStock: lowStock ?? this.lowStock,
        outOfStock: outOfStock ?? this.outOfStock,
        expiringSoon: expiringSoon ?? this.expiringSoon,
        expired: expired ?? this.expired,
      );
}

class GeneratedReportFile {
  const GeneratedReportFile({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  bool get isPdf => mimeType == 'application/pdf';
}
