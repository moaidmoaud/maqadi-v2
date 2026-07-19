import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/expiry_models.dart';
import '../models/inventory_models.dart';
import '../models/report_models.dart';
import '../models/shopping_models.dart';
import '../models/stock_models.dart';
import 'inventory_service.dart';

typedef ReportClock = DateTime Function();
typedef ReportFontLoader = Future<pw.Font> Function();

abstract interface class ReportGenerator {
  List<String> get categories;

  Future<GeneratedReportFile> generatePdf(
    PdfReportType type, {
    ReportFilter filter = const ReportFilter(),
    Iterable<GroceryItem> shoppingItems = const [],
  });

  GeneratedReportFile generateExcel({
    ReportFilter filter = const ReportFilter(),
    Iterable<GroceryItem> shoppingItems = const [],
  });

  GeneratedReportFile generateCsv(
    CsvReportType type, {
    ReportFilter filter = const ReportFilter(),
    Iterable<GroceryItem> shoppingItems = const [],
  });
}

class ReportService implements ReportGenerator {
  ReportService({
    required InventoryService inventoryService,
    ReportClock? clock,
    ReportFontLoader? regularFontLoader,
    ReportFontLoader? boldFontLoader,
    this.appName = 'مقاضي',
    this.appVersion = '0.3.1+31',
  })  : _inventory = inventoryService,
        _clock = clock ?? DateTime.now,
        _regularFontLoader =
            regularFontLoader ?? PdfGoogleFonts.notoSansArabicRegular,
        _boldFontLoader = boldFontLoader ?? PdfGoogleFonts.notoSansArabicBold;

  final InventoryService _inventory;
  final ReportClock _clock;
  final ReportFontLoader _regularFontLoader;
  final ReportFontLoader _boldFontLoader;
  final String appName;
  final String appVersion;

  @override
  List<String> get categories {
    final result =
        _inventory.items.map((item) => item.category).toSet().toList()..sort();
    return List.unmodifiable(result);
  }

  @override
  Future<GeneratedReportFile> generatePdf(
    PdfReportType type, {
    ReportFilter filter = const ReportFilter(),
    Iterable<GroceryItem> shoppingItems = const [],
  }) async {
    final generatedAt = _clock();
    final items = _filteredItems(filter);
    final groceries = _filteredGroceries(shoppingItems, filter);
    final regular = await _regularFontLoader();
    final bold = await _boldFontLoader();
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final document = pw.Document(theme: theme);
    final accent = PdfColor.fromHex('#2E7D32');

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 30),
        header: (context) => _pdfHeader(
          type,
          generatedAt,
          accent,
          context.pageNumber,
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('$appName • $appVersion'),
              pw.Text('الصفحة ${context.pageNumber} من ${context.pagesCount}'),
            ],
          ),
        ),
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _pdfSummary(_totals(items), accent),
                pw.SizedBox(height: 18),
                ..._pdfBody(type, items, groceries, accent),
              ],
            ),
          ),
        ],
      ),
    );

    return GeneratedReportFile(
      fileName: _fileName(_pdfFileStem(type), generatedAt, 'pdf'),
      mimeType: 'application/pdf',
      bytes: await document.save(),
    );
  }

  @override
  GeneratedReportFile generateExcel({
    ReportFilter filter = const ReportFilter(),
    Iterable<GroceryItem> shoppingItems = const [],
  }) {
    final generatedAt = _clock();
    final items = _filteredItems(filter);
    final groceries = _filteredGroceries(shoppingItems, filter);
    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet()!;
    workbook.rename(defaultSheet, 'Inventory');

    final inventorySheet = workbook['Inventory'];
    _appendMetadata(inventorySheet, generatedAt);
    _appendRow(inventorySheet, const [
      'Product',
      'Category',
      'Quantity',
      'Unit',
      'Minimum',
      'Stock Status',
      'Location',
      'Primary Barcode',
    ]);
    for (final item in items) {
      final stock = _inventory.stockInfoFor(item);
      _appendRow(inventorySheet, [
        item.name,
        item.category,
        item.quantity,
        item.unit,
        item.minimum,
        _stockLabel(stock.status),
        item.location,
        item.primaryBarcode ?? '',
      ]);
    }

    final shoppingSheet = workbook['Shopping List'];
    _appendMetadata(shoppingSheet, generatedAt);
    _appendRow(shoppingSheet, const [
      'Product',
      'Category',
      'Requested Quantity',
      'Completed',
      'Stock Status',
    ]);
    for (final grocery in groceries) {
      _appendRow(shoppingSheet, [
        grocery.name,
        grocery.category,
        grocery.quantity,
        grocery.done ? 'Yes' : 'No',
        _groceryStockLabel(grocery),
      ]);
    }

    final batchSheet = workbook['Batch Details'];
    _appendMetadata(batchSheet, generatedAt);
    _appendRow(batchSheet, const [
      'Product',
      'Category',
      'Batch ID',
      'Quantity',
      'Purchase Date',
      'Expiry Date',
      'Expiry Status',
      'Days Remaining',
      'Notes',
    ]);
    for (final item in items) {
      for (final batch in _inventory.batchesFor(item)) {
        final expiry = _inventory.expiryFor(item, batch);
        _appendRow(batchSheet, [
          item.name,
          item.category,
          batch.id,
          batch.quantity,
          _formatDate(batch.receivedAt),
          batch.expiresAt == null ? '' : _formatDate(batch.expiresAt!),
          _expiryLabel(expiry.status),
          expiry.daysRemaining ?? '',
          batch.note ?? '',
        ]);
      }
    }

    final dashboardSheet = workbook['Dashboard Summary'];
    _appendMetadata(dashboardSheet, generatedAt);
    _appendRow(dashboardSheet, const ['Metric', 'Value']);
    for (final row in _dashboardRows(items, groceries.length)) {
      _appendRow(dashboardSheet, row);
    }

    return GeneratedReportFile(
      fileName: _fileName('maqadi_export', generatedAt, 'xlsx'),
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      bytes: Uint8List.fromList(workbook.encode()!),
    );
  }

  @override
  GeneratedReportFile generateCsv(
    CsvReportType type, {
    ReportFilter filter = const ReportFilter(),
    Iterable<GroceryItem> shoppingItems = const [],
  }) {
    final generatedAt = _clock();
    final rows = <List<dynamic>>[];
    if (type == CsvReportType.inventory) {
      rows.add(const [
        'المنتج',
        'التصنيف',
        'الكمية',
        'الوحدة',
        'الحد الأدنى',
        'حالة المخزون',
        'الموقع',
        'الباركود',
      ]);
      for (final item in _filteredItems(filter)) {
        rows.add([
          item.name,
          item.category,
          item.quantity,
          item.unit,
          item.minimum,
          _stockLabel(_inventory.stockInfoFor(item).status),
          item.location,
          item.primaryBarcode ?? '',
        ]);
      }
    } else {
      rows.add(const [
        'المنتج',
        'التصنيف',
        'الكمية المطلوبة',
        'مكتمل',
        'حالة المخزون',
      ]);
      for (final grocery in _filteredGroceries(shoppingItems, filter)) {
        rows.add([
          grocery.name,
          grocery.category,
          grocery.quantity,
          grocery.done ? 'نعم' : 'لا',
          _groceryStockLabel(grocery),
        ]);
      }
    }
    final encoded = Csv(addBom: true).encode(rows);
    return GeneratedReportFile(
      fileName: _fileName(
        type == CsvReportType.inventory
            ? 'maqadi_inventory'
            : 'maqadi_shopping_list',
        generatedAt,
        'csv',
      ),
      mimeType: 'text/csv',
      bytes: Uint8List.fromList(utf8.encode(encoded)),
    );
  }

  List<PantryItem> _filteredItems(ReportFilter filter) {
    final result = _inventory.items.where((item) {
      if (filter.category != null && item.category != filter.category) {
        return false;
      }
      if (!filter.hasStatusFilter) return true;
      final stock = _inventory.stockInfoFor(item).status;
      final stockMatch = (filter.lowStock && stock == StockStatus.lowStock) ||
          (filter.outOfStock && stock == StockStatus.outOfStock);
      final expiryMatch = item.batches
          .where((batch) => batch.quantity > 0)
          .map((batch) => _inventory.expiryFor(item, batch).status)
          .any(
            (status) =>
                (filter.expiringSoon &&
                    status == BatchExpiryStatus.expiringSoon) ||
                (filter.expired && status == BatchExpiryStatus.expired),
          );
      return stockMatch || expiryMatch;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<GroceryItem> _filteredGroceries(
    Iterable<GroceryItem> groceries,
    ReportFilter filter,
  ) {
    final includedIds = _filteredItems(filter).map((item) => item.id).toSet();
    final result = groceries.where((grocery) {
      if (filter.category != null && grocery.category != filter.category) {
        return false;
      }
      if (!filter.hasStatusFilter) return true;
      final pantryId = grocery.pantryItemId;
      return pantryId != null && includedIds.contains(pantryId);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  pw.Widget _pdfHeader(
    PdfReportType type,
    DateTime generatedAt,
    PdfColor accent,
    int pageNumber,
  ) {
    if (pageNumber > 1) return pw.SizedBox(height: 8);
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 18),
        padding: const pw.EdgeInsets.all(16),
        decoration: pw.BoxDecoration(
          color: accent,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _pdfTitle(type),
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'تاريخ الإنشاء: ${_formatDateTime(generatedAt)}',
                  style: const pw.TextStyle(color: PdfColors.white),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  appName,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  appVersion,
                  style: const pw.TextStyle(color: PdfColors.white),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _pdfSummary(_ReportTotals totals, PdfColor accent) => pw.Row(
        children: [
          _summaryBox('إجمالي المنتجات', '${totals.products}', accent),
          pw.SizedBox(width: 8),
          _summaryBox('إجمالي الدفعات', '${totals.batches}', accent),
          pw.SizedBox(width: 8),
          _summaryBox('إجمالي الكمية', _quantity(totals.quantity), accent),
        ],
      );

  pw.Widget _summaryBox(String label, String value, PdfColor accent) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: PdfColor(accent.red, accent.green, accent.blue, 0.08),
            border: pw.Border.all(color: accent),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            children: [
              pw.Text(value,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: accent,
                  )),
              pw.Text(label),
            ],
          ),
        ),
      );

  List<pw.Widget> _pdfBody(
    PdfReportType type,
    List<PantryItem> items,
    List<GroceryItem> groceries,
    PdfColor accent,
  ) {
    switch (type) {
      case PdfReportType.currentInventory:
        return [
          _pdfTable(
            const ['المنتج', 'التصنيف', 'الكمية', 'الحد الأدنى', 'الحالة'],
            items
                .map((item) => [
                      item.name,
                      item.category,
                      '${_quantity(item.quantity)} ${item.unit}',
                      _quantity(item.minimum),
                      _stockLabel(_inventory.stockInfoFor(item).status),
                    ])
                .toList(),
            accent,
          ),
        ];
      case PdfReportType.shoppingList:
        return [
          _pdfTable(
            const ['المنتج', 'التصنيف', 'الكمية', 'مكتمل', 'حالة المخزون'],
            groceries
                .map((item) => [
                      item.name,
                      item.category,
                      '${item.quantity}',
                      item.done ? 'نعم' : 'لا',
                      _groceryStockLabel(item),
                    ])
                .toList(),
            accent,
          ),
        ];
      case PdfReportType.expiringSoon:
        return [_expiryPdfTable(items, BatchExpiryStatus.expiringSoon, accent)];
      case PdfReportType.expired:
        return [_expiryPdfTable(items, BatchExpiryStatus.expired, accent)];
      case PdfReportType.lowStock:
        final low = items
            .where(
              (item) =>
                  _inventory.stockInfoFor(item).status == StockStatus.lowStock,
            )
            .toList();
        return [
          _pdfTable(
            const ['المنتج', 'التصنيف', 'المتاح', 'الحد الأدنى', 'الوحدة'],
            low
                .map((item) => [
                      item.name,
                      item.category,
                      _quantity(item.quantity),
                      _quantity(item.minimum),
                      item.unit,
                    ])
                .toList(),
            accent,
          ),
        ];
      case PdfReportType.dashboardSummary:
        return [
          _pdfTable(
            const ['المؤشر', 'القيمة'],
            _dashboardRows(items, groceries.length)
                .map((row) => row.map((value) => '$value').toList())
                .toList(),
            accent,
          ),
        ];
    }
  }

  pw.Widget _expiryPdfTable(
    List<PantryItem> items,
    BatchExpiryStatus status,
    PdfColor accent,
  ) {
    final rows = <List<String>>[];
    for (final item in items) {
      for (final batch in _inventory.batchesFor(item)) {
        final expiry = _inventory.expiryFor(item, batch);
        if (expiry.status != status) continue;
        rows.add([
          item.name,
          batch.id,
          _quantity(batch.quantity),
          batch.expiresAt == null ? '—' : _formatDate(batch.expiresAt!),
          _remainingDays(expiry.daysRemaining),
        ]);
      }
    }
    rows.sort((a, b) => a[3].compareTo(b[3]));
    return _pdfTable(
      const ['المنتج', 'الدفعة', 'الكمية', 'تاريخ الانتهاء', 'المتبقي'],
      rows,
      accent,
    );
  }

  pw.Widget _pdfTable(
    List<String> headers,
    List<List<String>> rows,
    PdfColor accent,
  ) {
    if (rows.isEmpty) {
      return pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.all(28),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Text('لا توجد بيانات تطابق عوامل التصفية'),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerDecoration: pw.BoxDecoration(color: accent),
      headerStyle: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
      ),
      cellAlignment: pw.Alignment.centerRight,
      headerAlignment: pw.Alignment.centerRight,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
    );
  }

  List<List<Object>> _dashboardRows(
    List<PantryItem> items,
    int shoppingCount,
  ) {
    var low = 0;
    var out = 0;
    var expiring = 0;
    var expired = 0;
    for (final item in items) {
      switch (_inventory.stockInfoFor(item).status) {
        case StockStatus.lowStock:
          low++;
        case StockStatus.outOfStock:
          out++;
        case StockStatus.normalStock:
          break;
      }
      for (final batch in _inventory.batchesFor(item)) {
        switch (_inventory.expiryFor(item, batch).status) {
          case BatchExpiryStatus.expiringSoon:
            expiring++;
          case BatchExpiryStatus.expired:
            expired++;
          case BatchExpiryStatus.fresh:
            break;
        }
      }
    }
    final totals = _totals(items);
    return [
      ['إجمالي المنتجات', totals.products],
      ['إجمالي الدفعات', totals.batches],
      ['إجمالي الكمية', totals.quantity],
      ['مخزون منخفض', low],
      ['نفد المخزون', out],
      ['قريب الانتهاء', expiring],
      ['منتهي الصلاحية', expired],
      ['عناصر قائمة التسوق', shoppingCount],
    ];
  }

  _ReportTotals _totals(Iterable<PantryItem> items) {
    var products = 0;
    var batches = 0;
    var quantity = 0.0;
    for (final item in items) {
      products++;
      batches += _inventory.batchesFor(item).length;
      quantity += item.quantity;
    }
    return _ReportTotals(products, batches, quantity);
  }

  void _appendMetadata(Sheet sheet, DateTime generatedAt) {
    _appendRow(sheet, ['$appName $appVersion']);
    _appendRow(sheet, ['Generated', _formatDateTime(generatedAt)]);
    _appendRow(sheet, const []);
  }

  void _appendRow(Sheet sheet, List<Object> values) {
    sheet.appendRow(values.map<CellValue?>((value) {
      if (value is int) return IntCellValue(value);
      if (value is double) return DoubleCellValue(value);
      return TextCellValue(value.toString());
    }).toList());
  }

  String _groceryStockLabel(GroceryItem grocery) {
    final stock = _inventory.stockInfoForGrocery(grocery);
    return stock == null ? 'غير مرتبط بالمخزون' : _stockLabel(stock.status);
  }

  String _stockLabel(StockStatus status) => switch (status) {
        StockStatus.normalStock => 'مخزون طبيعي',
        StockStatus.lowStock => 'مخزون منخفض',
        StockStatus.outOfStock => 'نفد المخزون',
      };

  String _expiryLabel(BatchExpiryStatus status) => switch (status) {
        BatchExpiryStatus.fresh => 'طازج',
        BatchExpiryStatus.expiringSoon => 'قريب الانتهاء',
        BatchExpiryStatus.expired => 'منتهي الصلاحية',
      };

  String _remainingDays(int? days) => switch (days) {
        null => 'غير محدد',
        < 0 => 'منتهي منذ ${days.abs()} يوم',
        0 => 'اليوم',
        1 => 'يوم واحد',
        _ => '$days يومًا',
      };

  String _pdfTitle(PdfReportType type) => switch (type) {
        PdfReportType.currentInventory => 'تقرير المخزون الحالي',
        PdfReportType.shoppingList => 'تقرير قائمة التسوق',
        PdfReportType.expiringSoon => 'تقرير المنتجات قريبة الانتهاء',
        PdfReportType.expired => 'تقرير المنتجات منتهية الصلاحية',
        PdfReportType.lowStock => 'تقرير المخزون المنخفض',
        PdfReportType.dashboardSummary => 'ملخص لوحة المعلومات',
      };

  String _pdfFileStem(PdfReportType type) => switch (type) {
        PdfReportType.currentInventory => 'maqadi_inventory_report',
        PdfReportType.shoppingList => 'maqadi_shopping_report',
        PdfReportType.expiringSoon => 'maqadi_expiring_report',
        PdfReportType.expired => 'maqadi_expired_report',
        PdfReportType.lowStock => 'maqadi_low_stock_report',
        PdfReportType.dashboardSummary => 'maqadi_dashboard_report',
      };

  String _fileName(String stem, DateTime date, String extension) =>
      '${stem}_${date.year}${_two(date.month)}${_two(date.day)}_'
      '${_two(date.hour)}${_two(date.minute)}.$extension';

  String _formatDate(DateTime date) =>
      '${date.year}-${_two(date.month)}-${_two(date.day)}';

  String _formatDateTime(DateTime date) =>
      '${_formatDate(date)} ${_two(date.hour)}:${_two(date.minute)}';

  String _two(int value) => value.toString().padLeft(2, '0');

  String _quantity(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

class _ReportTotals {
  const _ReportTotals(this.products, this.batches, this.quantity);

  final int products;
  final int batches;
  final double quantity;
}
