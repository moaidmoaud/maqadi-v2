import 'package:flutter/material.dart';

import '../app_store.dart';
import '../models/report_models.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportFilter _filter = const ReportFilter();
  PdfReportType _pdfType = PdfReportType.currentInventory;
  CsvReportType _csvType = CsvReportType.inventory;
  bool _busy = false;

  Future<void> _run(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إنشاء الملف: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sharePdf() => _run(
        () async {
          final file = await widget.store.generatePdfReport(
            _pdfType,
            filter: _filter,
          );
          await widget.store.shareReport(file);
        },
        successMessage: 'تم تجهيز تقرير PDF للمشاركة',
      );

  Future<void> _printPdf() => _run(
        () async {
          final file = await widget.store.generatePdfReport(
            _pdfType,
            filter: _filter,
          );
          await widget.store.printReport(file);
        },
        successMessage: 'تم إرسال التقرير إلى الطباعة',
      );

  Future<void> _shareExcel() => _run(
        () async {
          final file = widget.store.generateExcelReport(filter: _filter);
          await widget.store.shareReport(file);
        },
        successMessage: 'تم تجهيز ملف Excel للمشاركة',
      );

  Future<void> _shareCsv() => _run(
        () async {
          final file = widget.store.generateCsvReport(
            _csvType,
            filter: _filter,
          );
          await widget.store.shareReport(file);
        },
        successMessage: 'تم تجهيز ملف CSV للمشاركة',
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('reports-screen'),
        appBar: AppBar(title: const Text('التقارير والتصدير')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _FilterCard(
              categories: widget.store.reportCategories,
              filter: _filter,
              onChanged: (filter) => setState(() => _filter = filter),
            ),
            const SizedBox(height: 14),
            _ExportCard(
              icon: Icons.picture_as_pdf_outlined,
              title: 'تقارير PDF',
              description: 'تقارير احترافية قابلة للمشاركة والطباعة المباشرة.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<PdfReportType>(
                    key: const ValueKey('pdf-report-type'),
                    initialValue: _pdfType,
                    decoration: const InputDecoration(
                      labelText: 'نوع التقرير',
                      border: OutlineInputBorder(),
                    ),
                    items: PdfReportType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(_pdfTypeLabel(type)),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _pdfType = value!),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        key: const ValueKey('share-pdf-report'),
                        onPressed: _busy ? null : _sharePdf,
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('إنشاء ومشاركة'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('print-pdf-report'),
                        onPressed: _busy ? null : _printPdf,
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('طباعة'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ExportCard(
              icon: Icons.table_view_outlined,
              title: 'تصدير Excel',
              description:
                  'المخزون وقائمة التسوق وتفاصيل الدفعات وملخص لوحة المعلومات في أوراق منفصلة.',
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('export-excel-report'),
                  onPressed: _busy ? null : _shareExcel,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('إنشاء ومشاركة Excel'),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _ExportCard(
              icon: Icons.description_outlined,
              title: 'تصدير CSV',
              description: 'ملف خفيف للمخزون أو قائمة التسوق.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<CsvReportType>(
                    key: const ValueKey('csv-report-type'),
                    segments: const [
                      ButtonSegment(
                        value: CsvReportType.inventory,
                        label: Text('المخزون'),
                      ),
                      ButtonSegment(
                        value: CsvReportType.shoppingList,
                        label: Text('قائمة التسوق'),
                      ),
                    ],
                    selected: {_csvType},
                    onSelectionChanged: _busy
                        ? null
                        : (values) => setState(() => _csvType = values.single),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const ValueKey('export-csv-report'),
                      onPressed: _busy ? null : _shareCsv,
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('إنشاء ومشاركة CSV'),
                    ),
                  ),
                ],
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      );
}

class _FilterCard extends StatelessWidget {
  const _FilterCard({
    required this.categories,
    required this.filter,
    required this.onChanged,
  });

  final List<String> categories;
  final ReportFilter filter;
  final ValueChanged<ReportFilter> onChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تصفية البيانات',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const ValueKey('report-category-filter'),
                initialValue: filter.category,
                decoration: const InputDecoration(
                  labelText: 'التصنيف',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('الكل')),
                  ...categories.map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  ),
                ],
                onChanged: (category) => onChanged(
                  category == null
                      ? filter.copyWith(clearCategory: true)
                      : filter.copyWith(category: category),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilterChip(
                    key: const ValueKey('report-filter-low'),
                    label: const Text('مخزون منخفض'),
                    selected: filter.lowStock,
                    onSelected: (value) =>
                        onChanged(filter.copyWith(lowStock: value)),
                  ),
                  FilterChip(
                    key: const ValueKey('report-filter-out'),
                    label: const Text('نفد المخزون'),
                    selected: filter.outOfStock,
                    onSelected: (value) =>
                        onChanged(filter.copyWith(outOfStock: value)),
                  ),
                  FilterChip(
                    key: const ValueKey('report-filter-expiring'),
                    label: const Text('قريب الانتهاء'),
                    selected: filter.expiringSoon,
                    onSelected: (value) =>
                        onChanged(filter.copyWith(expiringSoon: value)),
                  ),
                  FilterChip(
                    key: const ValueKey('report-filter-expired'),
                    label: const Text('منتهي الصلاحية'),
                    selected: filter.expired,
                    onSelected: (value) =>
                        onChanged(filter.copyWith(expired: value)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(description),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      );
}

String _pdfTypeLabel(PdfReportType type) => switch (type) {
      PdfReportType.currentInventory => 'المخزون الحالي',
      PdfReportType.shoppingList => 'قائمة التسوق',
      PdfReportType.expiringSoon => 'قريب الانتهاء',
      PdfReportType.expired => 'منتهي الصلاحية',
      PdfReportType.lowStock => 'المخزون المنخفض',
      PdfReportType.dashboardSummary => 'ملخص لوحة المعلومات',
    };
