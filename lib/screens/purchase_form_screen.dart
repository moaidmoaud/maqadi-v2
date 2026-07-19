import 'package:flutter/material.dart';

import '../models/purchase_models.dart';
import '../services/purchase_service.dart';

class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({
    super.key,
    required this.service,
    this.initialPurchase,
    this.initialItems = const [],
  });

  final PurchaseService service;
  final Purchase? initialPurchase;
  final List<PurchaseItem> initialItems;

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  late final TextEditingController _storeController;
  late final TextEditingController _notesController;
  late final TextEditingController _discountController;
  late final TextEditingController _taxController;
  late final String _purchaseId;
  late DateTime _purchaseDate;
  late final List<PurchaseProductOption> _products;
  late final List<_PurchaseItemEditor> _items;
  List<String> _stores = const [];
  PurchaseTotals? _totals;
  bool _busy = false;

  bool get _editing => widget.initialPurchase != null;

  @override
  void initState() {
    super.initState();
    final purchase = widget.initialPurchase;
    _purchaseId = purchase?.id ?? widget.service.newPurchaseId();
    _purchaseDate = purchase?.purchaseDate ?? DateTime.now();
    _products = widget.service.availableProducts();
    _storeController = TextEditingController(text: purchase?.storeId ?? '');
    _notesController = TextEditingController(text: purchase?.notes ?? '');
    _discountController = TextEditingController(
      text: purchase == null ? '0' : purchase.discount.toStringAsFixed(2),
    );
    _taxController = TextEditingController(
      text: purchase == null ? '0' : purchase.tax.toStringAsFixed(2),
    );
    _items = widget.initialItems
        .map(
          (item) => _PurchaseItemEditor(item: item, onChanged: _refreshTotals),
        )
        .toList();
    _discountController.addListener(_refreshTotals);
    _taxController.addListener(_refreshTotals);
    widget.service.readStoreIds().then((stores) {
      if (mounted) setState(() => _stores = stores);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshTotals());
  }

  @override
  void dispose() {
    _discountController
      ..removeListener(_refreshTotals)
      ..dispose();
    _taxController
      ..removeListener(_refreshTotals)
      ..dispose();
    _storeController.dispose();
    _notesController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _refreshTotals() {
    if (!mounted) return;
    PurchaseTotals? totals;
    try {
      totals = widget.service.previewTotals(
        _purchaseItems(),
        discount: _amount(_discountController.text),
        tax: _amount(_taxController.text),
      );
    } catch (_) {
      totals = null;
    }
    setState(() => _totals = totals);
  }

  List<PurchaseItem> _purchaseItems() => _items
      .map(
        (editor) => editor.item.copyWith(
          purchaseId: _purchaseId,
          quantity: _number(editor.quantityController.text),
          unitPrice: _number(editor.priceController.text),
          finalUnitPrice: _number(editor.priceController.text),
          lineTotal: 0,
          expiryDate: editor.expiryDate,
          clearExpiryDate: editor.expiryDate == null,
        ),
      )
      .toList();

  Future<void> _addProduct() async {
    if (_products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف منتجًا إلى المخزن أولًا.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<PurchaseProductOption>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          key: const ValueKey('purchase-product-picker'),
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'اختر منتجًا',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
            for (final product in _products)
              ListTile(
                key: ValueKey('select-product-${product.id}'),
                title: Text(product.name),
                subtitle: Text('${product.category} • ${product.unit}'),
                onTap: () => Navigator.pop(context, product),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final item = widget.service.createDraftItem(
      selected.id,
      purchaseId: _purchaseId,
    );
    setState(() {
      _items.add(_PurchaseItemEditor(item: item, onChanged: _refreshTotals));
    });
    _refreshTotals();
  }

  void _removeItem(_PurchaseItemEditor editor) {
    setState(() => _items.remove(editor));
    editor.dispose();
    _refreshTotals();
  }

  Future<void> _pickPurchaseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) setState(() => _purchaseDate = selected);
  }

  Future<void> _pickExpiry(_PurchaseItemEditor editor) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: editor.expiryDate ?? _purchaseDate,
      firstDate: _purchaseDate,
      lastDate: DateTime(2200),
    );
    if (selected != null && mounted) {
      setState(() => editor.expiryDate = selected);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final items = _purchaseItems();
      final discount = _amount(_discountController.text);
      final tax = _amount(_taxController.text);
      if (_editing) {
        final source = widget.initialPurchase!;
        await widget.service.updatePurchase(
          purchase: source.copyWith(
            storeId: _storeController.text,
            purchaseDate: _purchaseDate,
            notes: _notesController.text,
            clearNotes: _notesController.text.trim().isEmpty,
          ),
          items: items,
          discountAmount: discount,
          taxAmount: tax,
        );
      } else {
        await widget.service.createPurchase(
          id: _purchaseId,
          storeId: _storeController.text,
          purchaseDate: _purchaseDate,
          items: items,
          discountAmount: discount,
          taxAmount: tax,
          notes: _notesController.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on PurchaseValidationException catch (error) {
      _showError(error.message);
    } on ArgumentError catch (error) {
      _showError(error.message?.toString() ?? error.toString());
    } catch (error) {
      _showError('تعذر حفظ عملية الشراء: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('purchase-form-screen'),
        appBar: AppBar(title: Text(_editing ? 'تعديل الشراء' : 'إضافة شراء')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
          children: [
            _PurchaseHeaderFields(
              storeController: _storeController,
              notesController: _notesController,
              purchaseDate: _purchaseDate,
              stores: _stores,
              onStoreSelected: (store) {
                _storeController.text = store;
                setState(() {});
              },
              onPickDate: _pickPurchaseDate,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'المنتجات',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                ),
                FilledButton.tonalIcon(
                  key: const ValueKey('add-purchase-product'),
                  onPressed: _busy ? null : _addProduct,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة منتج'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_items.isEmpty)
              const Card(
                key: ValueKey('purchase-items-empty'),
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('لم تتم إضافة منتجات بعد.'),
                ),
              ),
            for (final editor in _items) ...[
              _PurchaseItemEditorCard(
                key: ValueKey('purchase-item-${editor.item.id}'),
                editor: editor,
                productName:
                    widget.service.productNameFor(editor.item.productId),
                onPickExpiry: () => _pickExpiry(editor),
                onClearExpiry: () {
                  setState(() => editor.expiryDate = null);
                },
                onRemove: () => _removeItem(editor),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            _FinancialFields(
              discountController: _discountController,
              taxController: _taxController,
              totals: _totals,
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            key: const ValueKey('save-purchase'),
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_editing ? 'حفظ التعديلات' : 'حفظ الشراء'),
          ),
        ),
      );
}

class _PurchaseHeaderFields extends StatelessWidget {
  const _PurchaseHeaderFields({
    required this.storeController,
    required this.notesController,
    required this.purchaseDate,
    required this.stores,
    required this.onStoreSelected,
    required this.onPickDate,
  });

  final TextEditingController storeController;
  final TextEditingController notesController;
  final DateTime purchaseDate;
  final List<String> stores;
  final ValueChanged<String> onStoreSelected;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('purchase-store'),
                controller: storeController,
                decoration: const InputDecoration(
                  labelText: 'المتجر *',
                  border: OutlineInputBorder(),
                ),
              ),
              if (stores.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final store in stores)
                      ActionChip(
                        label: Text(store),
                        onPressed: () => onStoreSelected(store),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('purchase-date'),
                onPressed: onPickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('تاريخ الشراء: ${_formatDate(purchaseDate)}'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('purchase-notes'),
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      );
}

class _PurchaseItemEditorCard extends StatelessWidget {
  const _PurchaseItemEditorCard({
    super.key,
    required this.editor,
    required this.productName,
    required this.onPickExpiry,
    required this.onClearExpiry,
    required this.onRemove,
  });

  final _PurchaseItemEditor editor;
  final String productName;
  final VoidCallback onPickExpiry;
  final VoidCallback onClearExpiry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      productName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'إزالة المنتج',
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('quantity-${editor.item.id}'),
                      controller: editor.quantityController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'الكمية *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: ValueKey('unit-price-${editor.item.id}'),
                      controller: editor.priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'سعر الوحدة *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPickExpiry,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        editor.expiryDate == null
                            ? 'تاريخ الانتهاء (اختياري)'
                            : _formatDate(editor.expiryDate!),
                      ),
                    ),
                  ),
                  if (editor.expiryDate != null)
                    IconButton(
                      tooltip: 'مسح تاريخ الانتهاء',
                      onPressed: onClearExpiry,
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
              if (editor.item.batchId case final batchId?)
                Text('الدفعة المرتبطة: $batchId'),
            ],
          ),
        ),
      );
}

class _FinancialFields extends StatelessWidget {
  const _FinancialFields({
    required this.discountController,
    required this.taxController,
    required this.totals,
  });

  final TextEditingController discountController;
  final TextEditingController taxController;
  final PurchaseTotals? totals;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('purchase-discount'),
                      controller: discountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'الخصم',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('purchase-tax'),
                      controller: taxController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'الضريبة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              _TotalRow(label: 'الإجمالي الفرعي', value: totals?.subtotal),
              _TotalRow(label: 'الخصم', value: totals?.discount),
              _TotalRow(label: 'الضريبة', value: totals?.tax),
              _TotalRow(
                  label: 'الإجمالي', value: totals?.total, emphasized: true),
            ],
          ),
        ),
      );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final double? value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: emphasized
                    ? const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)
                    : null,
              ),
            ),
            Text(
              value == null ? '—' : '${value!.toStringAsFixed(2)} ر.س',
              style: emphasized
                  ? const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)
                  : null,
            ),
          ],
        ),
      );
}

class _PurchaseItemEditor {
  _PurchaseItemEditor({required this.item, required this.onChanged})
      : quantityController = TextEditingController(
          text: _numberText(item.quantity),
        ),
        priceController = TextEditingController(
          text: _numberText(item.unitPrice),
        ),
        expiryDate = item.expiryDate {
    quantityController.addListener(onChanged);
    priceController.addListener(onChanged);
  }

  final PurchaseItem item;
  final VoidCallback onChanged;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  DateTime? expiryDate;

  void dispose() {
    quantityController
      ..removeListener(onChanged)
      ..dispose();
    priceController
      ..removeListener(onChanged)
      ..dispose();
  }
}

double _number(String value) => double.tryParse(value.trim()) ?? double.nan;

double _amount(String value) {
  final clean = value.trim();
  return clean.isEmpty ? 0 : double.tryParse(clean) ?? double.nan;
}

String _numberText(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _formatDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
