import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/models/report_models.dart';
import 'package:maqadi_v2/models/shopping_models.dart';
import 'package:maqadi_v2/screens/reports_screen.dart';
import 'package:maqadi_v2/services/report_delivery.dart';
import 'package:maqadi_v2/services/report_service.dart';

void main() {
  testWidgets('reports screen exposes formats, filters, sharing, and printing',
      (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final generator = _FakeReportGenerator();
    final delivery = _FakeReportDelivery();
    final store = AppStore(
      reportGenerator: generator,
      reportDelivery: delivery,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ReportsScreen(store: store),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('reports-screen')), findsOneWidget);
    expect(find.text('تقارير PDF'), findsOneWidget);
    expect(find.text('تصدير Excel'), findsOneWidget);
    expect(find.text('تصدير CSV'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report-filter-low')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('share-pdf-report')));
    await tester.pumpAndSettle();

    expect(generator.lastFilter?.lowStock, isTrue);
    expect(delivery.shared, hasLength(1));
    expect(delivery.shared.single.isPdf, isTrue);

    await tester.tap(find.byKey(const ValueKey('print-pdf-report')));
    await tester.pumpAndSettle();
    expect(delivery.printed, hasLength(1));

    await tester.ensureVisible(
      find.byKey(const ValueKey('export-excel-report')),
    );
    await tester.tap(find.byKey(const ValueKey('export-excel-report')));
    await tester.pumpAndSettle();
    expect(delivery.shared.last.fileName, 'report.xlsx');

    await tester.ensureVisible(find.byKey(const ValueKey('export-csv-report')));
    await tester.tap(find.byKey(const ValueKey('export-csv-report')));
    await tester.pumpAndSettle();
    expect(delivery.shared.last.fileName, 'report.csv');
    store.dispose();
  });
}

class _FakeReportGenerator implements ReportGenerator {
  ReportFilter? lastFilter;

  @override
  List<String> get categories => const ['الحبوب', 'الألبان'];

  @override
  GeneratedReportFile generateCsv(
    CsvReportType type, {
    ReportFilter filter = const ReportFilter(),
    Iterable<GroceryItem> shoppingItems = const [],
  }) {
    lastFilter = filter;
    return GeneratedReportFile(
      fileName: 'report.csv',
      mimeType: 'text/csv',
      bytes: Uint8List.fromList([1]),
    );
  }

  @override
  GeneratedReportFile generateExcel({
    ReportFilter filter = const ReportFilter(),
    Iterable<GroceryItem> shoppingItems = const [],
  }) {
    lastFilter = filter;
    return GeneratedReportFile(
      fileName: 'report.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      bytes: Uint8List.fromList([1]),
    );
  }

  @override
  Future<GeneratedReportFile> generatePdf(
    PdfReportType type, {
    ReportFilter filter = const ReportFilter(),
    Iterable<GroceryItem> shoppingItems = const [],
  }) async {
    lastFilter = filter;
    return GeneratedReportFile(
      fileName: 'report.pdf',
      mimeType: 'application/pdf',
      bytes: Uint8List.fromList([1]),
    );
  }
}

class _FakeReportDelivery implements ReportDelivery {
  final List<GeneratedReportFile> shared = [];
  final List<GeneratedReportFile> printed = [];

  @override
  Future<void> printPdf(GeneratedReportFile file) async => printed.add(file);

  @override
  Future<void> share(GeneratedReportFile file) async => shared.add(file);
}
