import 'package:flutter/material.dart';

import '../models/purchase_models.dart';
import '../services/purchase_service.dart';
import 'purchase_details_screen.dart';
import 'purchase_form_screen.dart';

class PurchaseListScreen extends StatefulWidget {
  const PurchaseListScreen({super.key, required this.service});

  final PurchaseService service;

  @override
  State<PurchaseListScreen> createState() => _PurchaseListScreenState();
}

class _PurchaseListScreenState extends State<PurchaseListScreen> {
  final _searchController = TextEditingController();
  List<PurchaseListEntry> _entries = const [];
  List<String> _stores = const [];
  String? _storeId;
  DateTime? _date;
  DateTimeRange? _range;
  Object? _error;
  bool _loading = true;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_reloadWithoutSpinner);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_reloadWithoutSpinner)
      ..dispose();
    super.dispose();
  }

  void _reloadWithoutSpinner() => _load(showSpinner: false);

  Future<void> _load({bool showSpinner = true}) async {
    final version = ++_loadVersion;
    if (showSpinner && mounted) setState(() => _loading = true);
    try {
      final stores = await widget.service.readStoreIds();
      final entries = await widget.service.searchPurchases(
        query: _searchController.text,
        storeId: _storeId,
        date: _date,
        startDate: _range?.start,
        endDate: _range?.end,
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _stores = stores;
        _entries = entries;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _date = selected;
      _range = null;
    });
    await _load();
  }

  Future<void> _pickRange() async {
    final selected = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _range = selected;
      _date = null;
    });
    await _load();
  }

  Future<void> _openCreate() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: PurchaseFormScreen(service: widget.service),
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _openDetails(Purchase purchase) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: PurchaseDetailsScreen(
            service: widget.service,
            purchaseId: purchase.id,
          ),
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  void _clearDates() {
    setState(() {
      _date = null;
      _range = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('purchase-list-screen'),
        appBar: AppBar(title: const Text('سجل المشتريات')),
        floatingActionButton: FloatingActionButton.extended(
          key: const ValueKey('create-purchase'),
          onPressed: _openCreate,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('إضافة شراء'),
        ),
        body: Column(
          children: [
            _PurchaseFilters(
              searchController: _searchController,
              stores: _stores,
              storeId: _storeId,
              date: _date,
              range: _range,
              onStoreChanged: (value) {
                setState(() => _storeId = value);
                _load();
              },
              onDate: _pickDate,
              onRange: _pickRange,
              onClearDates: _clearDates,
            ),
            Expanded(child: _buildContent()),
          ],
        ),
      );

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        key: ValueKey('purchase-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return _PurchaseError(error: _error!, onRetry: _load);
    }
    if (_entries.isEmpty) {
      return const _PurchaseEmptyState();
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final purchase = entry.purchase;
          return Card(
            child: ListTile(
              key: ValueKey('purchase-${purchase.id}'),
              leading: const CircleAvatar(
                child: Icon(Icons.receipt_long_outlined),
              ),
              title: Text(
                purchase.storeId,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                '${_formatDate(purchase.purchaseDate)} • ${entry.itemCount} منتج',
              ),
              trailing: Text(
                '${purchase.total.toStringAsFixed(2)} ر.س',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              onTap: () => _openDetails(purchase),
            ),
          );
        },
      ),
    );
  }
}

class _PurchaseFilters extends StatelessWidget {
  const _PurchaseFilters({
    required this.searchController,
    required this.stores,
    required this.storeId,
    required this.date,
    required this.range,
    required this.onStoreChanged,
    required this.onDate,
    required this.onRange,
    required this.onClearDates,
  });

  final TextEditingController searchController;
  final List<String> stores;
  final String? storeId;
  final DateTime? date;
  final DateTimeRange? range;
  final ValueChanged<String?> onStoreChanged;
  final VoidCallback onDate;
  final VoidCallback onRange;
  final VoidCallback onClearDates;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                key: const ValueKey('purchase-search'),
                controller: searchController,
                decoration: const InputDecoration(
                  labelText: 'بحث في المشتريات',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                key: ValueKey('purchase-store-filter-$storeId'),
                initialValue: storeId,
                decoration: const InputDecoration(
                  labelText: 'المتجر',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('كل المتاجر')),
                  ...stores.map(
                    (store) =>
                        DropdownMenuItem(value: store, child: Text(store)),
                  ),
                ],
                onChanged: onStoreChanged,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('purchase-date-filter'),
                    onPressed: onDate,
                    icon: const Icon(Icons.today_outlined),
                    label:
                        Text(date == null ? 'تاريخ محدد' : _formatDate(date!)),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('purchase-range-filter'),
                    onPressed: onRange,
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      range == null
                          ? 'نطاق تاريخ'
                          : '${_formatDate(range!.start)} - ${_formatDate(range!.end)}',
                    ),
                  ),
                  if (date != null || range != null)
                    TextButton.icon(
                      onPressed: onClearDates,
                      icon: const Icon(Icons.clear),
                      label: const Text('مسح التاريخ'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _PurchaseEmptyState extends StatelessWidget {
  const _PurchaseEmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        key: ValueKey('purchase-empty'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined, size: 64),
              SizedBox(height: 12),
              Text('لا توجد مشتريات مطابقة'),
            ],
          ),
        ),
      );
}

class _PurchaseError extends StatelessWidget {
  const _PurchaseError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        key: const ValueKey('purchase-error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 10),
              Text('تعذر تحميل المشتريات: $error'),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

String _formatDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
