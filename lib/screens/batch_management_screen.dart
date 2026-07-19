import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_store.dart';
import '../models/expiry_models.dart';
import '../models/inventory_models.dart';
import '../models/stock_models.dart';
import '../screens/barcode_scanner_screen.dart';
import '../widgets/expiry_status_badge.dart';
import '../widgets/qr_code_dialog.dart';
import '../widgets/stock_status_badge.dart';

class BatchManagementScreen extends StatefulWidget {
  const BatchManagementScreen({
    super.key,
    required this.store,
    required this.item,
    this.initialBatchId,
    this.scannerBuilder,
  });

  final AppStore store;
  final PantryItem item;
  final String? initialBatchId;
  final BarcodeScannerBuilder? scannerBuilder;

  @override
  State<BatchManagementScreen> createState() => _BatchManagementScreenState();
}

class _BatchManagementScreenState extends State<BatchManagementScreen> {
  Future<void> _scanNewBarcode() async {
    final barcode = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) => BarcodeScannerScreen(
          scannerBuilder: widget.scannerBuilder,
        ),
      ),
    );
    if (barcode == null || !mounted) return;
    try {
      final changed = widget.store.addPantryBarcode(widget.item, barcode);
      if (changed) setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(changed ? 'تمت إضافة الباركود' : 'الباركود مسجل بالفعل'),
        ),
      );
    } on ArgumentError catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.message?.toString() ?? 'تعذر حفظ الباركود')),
      );
    }
  }

  Future<void> _copyBarcode(String barcode) async {
    await Clipboard.setData(ClipboardData(text: barcode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ الباركود')),
    );
  }

  void _makePrimaryBarcode(String barcode) {
    if (widget.store.makePrimaryPantryBarcode(widget.item, barcode)) {
      setState(() {});
    }
  }

  void _removeBarcode(String barcode) {
    if (widget.store.removePantryBarcode(widget.item, barcode)) {
      setState(() {});
    }
  }

  void _showProductQr() {
    showInventoryQrDialog(
      context,
      title: 'QR المنتج: ${widget.item.name}',
      payload: widget.store.productQrPayload(widget.item),
    );
  }

  void _showBatchQr(InventoryBatch batch) {
    showInventoryQrDialog(
      context,
      title: 'QR الدفعة: ${batch.id}',
      payload: widget.store.batchQrPayload(widget.item, batch),
    );
  }

  Future<void> _showBatchEditor([InventoryBatch? batch]) async {
    final draft = await showModalBottomSheet<_BatchDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BatchEditorSheet(batch: batch),
    );
    if (draft == null || !mounted) return;

    try {
      if (batch == null) {
        widget.store.addPantryBatch(
          widget.item,
          quantity: draft.quantity,
          purchasedAt: draft.purchasedAt,
          expiresAt: draft.expiresAt,
          batchId: draft.batchId,
          note: draft.note,
        );
      } else {
        widget.store.updatePantryBatch(
          widget.item,
          batch,
          quantity: draft.quantity,
          purchasedAt: draft.purchasedAt,
          expiresAt: draft.expiresAt,
          batchId: draft.batchId,
          note: draft.note,
        );
      }
      setState(() {});
    } on ArgumentError catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message?.toString() ?? 'تعذر حفظ الدفعة')),
      );
    }
  }

  Future<void> _deleteBatch(InventoryBatch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الدفعة'),
        content: Text(
          'سيتم خصم ${_formatQuantity(batch.quantity)} ${widget.item.unit} '
          'من إجمالي المخزون. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.store.deletePantryBatch(widget.item, batch);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final batches = widget.store.batchesFor(widget.item);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'دفعات ${widget.item.name}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showBatchEditor,
        icon: const Icon(Icons.add),
        label: const Text('إضافة دفعة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                _BatchSummary(
                  stockInfo: widget.store.stockInfoFor(widget.item),
                  unit: widget.item.unit,
                  batchCount: batches.length,
                ),
                const SizedBox(height: 10),
                _ProductBarcodeCard(
                  item: widget.item,
                  onCopy: _copyBarcode,
                  onGenerateQr: _showProductQr,
                  onScan: _scanNewBarcode,
                  onMakePrimary: _makePrimaryBarcode,
                  onRemove: _removeBarcode,
                ),
                if (widget.initialBatchId != null) ...[
                  const SizedBox(height: 10),
                  _OpenedBatchNotice(batchId: widget.initialBatchId!),
                ],
                const SizedBox(height: 10),
                const _FifoNotice(),
              ],
            ),
          ),
          Expanded(
            child: batches.isEmpty
                ? const _EmptyBatches()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: batches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final batch = batches[index];
                      return _BatchCard(
                        batch: batch,
                        expiryInfo: widget.store.expiryFor(widget.item, batch),
                        unit: widget.item.unit,
                        fifoPosition: index + 1,
                        highlighted: batch.id == widget.initialBatchId,
                        onEdit: () => _showBatchEditor(batch),
                        onDelete: () => _deleteBatch(batch),
                        onGenerateQr: () => _showBatchQr(batch),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProductBarcodeCard extends StatelessWidget {
  const _ProductBarcodeCard({
    required this.item,
    required this.onCopy,
    required this.onGenerateQr,
    required this.onScan,
    required this.onMakePrimary,
    required this.onRemove,
  });

  final PantryItem item;
  final ValueChanged<String> onCopy;
  final VoidCallback onGenerateQr;
  final VoidCallback onScan;
  final ValueChanged<String> onMakePrimary;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('product-barcode-card'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.qr_code_2),
                  SizedBox(width: 8),
                  Text(
                    'الباركود وQR',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _BarcodeRow(
                label: 'الباركود الأساسي',
                value: item.primaryBarcode,
                onCopy: onCopy,
                onRemove: item.primaryBarcode == null
                    ? null
                    : () => onRemove(item.primaryBarcode!),
              ),
              const SizedBox(height: 6),
              Text(
                'باركودات إضافية',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (item.additionalBarcodes.isEmpty)
                const Text('لا يوجد')
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final barcode in item.additionalBarcodes)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InputChip(
                            label: Text(barcode),
                            avatar: const Icon(Icons.qr_code_scanner, size: 18),
                            onPressed: () => onCopy(barcode),
                            onDeleted: () => onRemove(barcode),
                            deleteIcon: const Icon(Icons.close, size: 18),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'خيارات الباركود',
                            onSelected: (_) => onMakePrimary(barcode),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'primary',
                                child: Text('جعله أساسيًا'),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('generate-product-qr'),
                    onPressed: onGenerateQr,
                    icon: const Icon(Icons.qr_code_2),
                    label: const Text('إنشاء QR'),
                  ),
                  FilledButton.tonalIcon(
                    key: const ValueKey('scan-product-barcode'),
                    onPressed: onScan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('مسح باركود جديد'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _BarcodeRow extends StatelessWidget {
  const _BarcodeRow({
    required this.label,
    required this.value,
    required this.onCopy,
    this.onRemove,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onCopy;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                SelectableText(
                  value ?? 'غير محدد',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          if (value != null)
            IconButton(
              tooltip: 'نسخ الباركود',
              onPressed: () => onCopy(value!),
              icon: const Icon(Icons.copy_outlined),
            ),
          if (onRemove != null)
            IconButton(
              tooltip: 'حذف الباركود',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      );
}

class _OpenedBatchNotice extends StatelessWidget {
  const _OpenedBatchNotice({required this.batchId});

  final String batchId;

  @override
  Widget build(BuildContext context) => Material(
        key: const ValueKey('opened-batch-notice'),
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Text(
            'تم فتح الدفعة مباشرةً: $batchId',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
}

class _BatchSummary extends StatelessWidget {
  const _BatchSummary({
    required this.stockInfo,
    required this.unit,
    required this.batchCount,
  });

  final StockInfo stockInfo;
  final String unit;
  final int batchCount;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SummaryValue(
                      icon: Icons.inventory_2_outlined,
                      label: 'الكمية الحالية',
                      value:
                          '${_formatQuantity(stockInfo.currentQuantity)} $unit',
                    ),
                  ),
                  const SizedBox(height: 42, child: VerticalDivider()),
                  Expanded(
                    child: _SummaryValue(
                      icon: Icons.vertical_align_bottom_outlined,
                      label: 'الحد الأدنى',
                      value:
                          '${_formatQuantity(stockInfo.minimumQuantity)} $unit',
                    ),
                  ),
                  const SizedBox(height: 42, child: VerticalDivider()),
                  Expanded(
                    child: _SummaryValue(
                      icon: Icons.layers_outlined,
                      label: 'عدد الدفعات',
                      value: '$batchCount',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StockStatusBadge(info: stockInfo),
            ],
          ),
        ),
      );
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      );
}

class _FifoNotice extends StatelessWidget {
  const _FifoNotice();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.low_priority),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ترتيب FIFO: تُستهلك الدفعات الأقدم شراءً أولاً.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      );
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({
    required this.batch,
    required this.expiryInfo,
    required this.unit,
    required this.fifoPosition,
    required this.highlighted,
    required this.onEdit,
    required this.onDelete,
    required this.onGenerateQr,
  });

  final InventoryBatch batch;
  final BatchExpiryInfo expiryInfo;
  final String unit;
  final int fifoPosition;
  final bool highlighted;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onGenerateQr;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey('batch-card-${batch.id}'),
        color:
            highlighted ? Theme.of(context).colorScheme.primaryContainer : null,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                child: Text(
                  '$fifoPosition',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_formatQuantity(batch.quantity)} $unit',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 7),
                    ExpiryStatusBadge(info: expiryInfo),
                    const SizedBox(height: 6),
                    _BatchDetail(
                      icon: Icons.shopping_cart_outlined,
                      text: 'تاريخ الشراء: ${_formatDate(batch.receivedAt)}',
                    ),
                    _BatchDetail(
                      icon: Icons.event_busy_outlined,
                      text: batch.expiresAt == null
                          ? 'تاريخ الانتهاء: غير محدد'
                          : 'تاريخ الانتهاء: ${_formatDate(batch.expiresAt!)}',
                    ),
                    _BatchDetail(
                      icon: Icons.tag,
                      text: 'معرّف الدفعة: ${batch.id}',
                    ),
                    if (batch.note != null)
                      _BatchDetail(
                          icon: Icons.notes_outlined, text: batch.note!),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                  if (value == 'qr') onGenerateQr();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'qr', child: Text('إنشاء QR للدفعة')),
                  PopupMenuItem(value: 'edit', child: Text('تعديل الدفعة')),
                  PopupMenuItem(value: 'delete', child: Text('حذف الدفعة')),
                ],
              ),
            ],
          ),
        ),
      );
}

class _BatchDetail extends StatelessWidget {
  const _BatchDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      );
}

class _EmptyBatches extends StatelessWidget {
  const _EmptyBatches();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_clear_outlined, size: 64),
            SizedBox(height: 12),
            Text('لا توجد دفعات لهذا المنتج'),
            SizedBox(height: 4),
            Text('أضف دفعة لتحديث كمية المخزون'),
          ],
        ),
      );
}

class _BatchEditorSheet extends StatefulWidget {
  const _BatchEditorSheet({this.batch});

  final InventoryBatch? batch;

  @override
  State<_BatchEditorSheet> createState() => _BatchEditorSheetState();
}

class _BatchEditorSheetState extends State<_BatchEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantity;
  late final TextEditingController _batchId;
  late final TextEditingController _note;
  late DateTime _purchasedAt;
  DateTime? _expiresAt;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    final batch = widget.batch;
    _quantity = TextEditingController(
      text: batch == null ? '1' : _formatQuantity(batch.quantity),
    );
    _batchId = TextEditingController(text: batch?.id ?? '');
    _note = TextEditingController(text: batch?.note ?? '');
    _purchasedAt = batch?.receivedAt ?? DateTime.now();
    _expiresAt = batch?.expiresAt;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _batchId.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPurchaseDate() async {
    final selected = await _pickDate(_purchasedAt);
    if (selected == null) return;
    setState(() {
      _purchasedAt = selected;
      _dateError = null;
    });
  }

  Future<void> _pickExpiryDate() async {
    final selected = await _pickDate(_expiresAt ?? _purchasedAt);
    if (selected == null) return;
    setState(() {
      _expiresAt = selected;
      _dateError = null;
    });
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
        context: context,
        initialDate: _pickerDate(initial),
        firstDate: DateTime(1970),
        lastDate: DateTime(2100, 12, 31),
      );

  DateTime _pickerDate(DateTime value) {
    final date = DateUtils.dateOnly(value.toLocal());
    if (date.isBefore(DateTime(1970))) return DateTime(1970);
    if (date.isAfter(DateTime(2100, 12, 31))) return DateTime(2100, 12, 31);
    return date;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final expiry = _expiresAt;
    if (expiry != null && expiry.isBefore(DateUtils.dateOnly(_purchasedAt))) {
      setState(() {
        _dateError = 'تاريخ الانتهاء يجب ألا يسبق تاريخ الشراء';
      });
      return;
    }
    Navigator.pop(
      context,
      _BatchDraft(
        quantity: double.parse(_quantity.text.replaceAll(',', '.')),
        purchasedAt: _purchasedAt,
        expiresAt: expiry,
        batchId: _batchId.text.trim().isEmpty ? null : _batchId.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.batch == null ? 'إضافة دفعة' : 'تعديل الدفعة',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _quantity,
                  autofocus: widget.batch == null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'الكمية',
                    prefixIcon: Icon(Icons.numbers),
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(
                      (value ?? '').replaceAll(',', '.'),
                    );
                    return parsed == null || parsed <= 0
                        ? 'أدخل كمية أكبر من صفر'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: 'تاريخ الشراء',
                  value: _formatDate(_purchasedAt),
                  icon: Icons.shopping_cart_outlined,
                  onTap: _pickPurchaseDate,
                ),
                const SizedBox(height: 12),
                _DateField(
                  label: 'تاريخ الانتهاء (اختياري)',
                  value: _expiresAt == null
                      ? 'غير محدد'
                      : _formatDate(_expiresAt!),
                  icon: Icons.event_busy_outlined,
                  onTap: _pickExpiryDate,
                  onClear: _expiresAt == null
                      ? null
                      : () => setState(() {
                            _expiresAt = null;
                            _dateError = null;
                          }),
                ),
                if (_dateError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _dateError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _batchId,
                  decoration: const InputDecoration(
                    labelText: 'معرّف الدفعة (اختياري)',
                    hintText: 'يُنشأ تلقائيًا عند تركه فارغًا',
                    prefixIcon: Icon(Icons.tag),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ الدفعة'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            suffixIcon: onClear == null
                ? const Icon(Icons.calendar_month_outlined)
                : IconButton(
                    tooltip: 'مسح التاريخ',
                    onPressed: onClear,
                    icon: const Icon(Icons.clear),
                  ),
          ),
          child: Text(value),
        ),
      );
}

class _BatchDraft {
  const _BatchDraft({
    required this.quantity,
    required this.purchasedAt,
    this.expiresAt,
    this.batchId,
    this.note,
  });

  final double quantity;
  final DateTime purchasedAt;
  final DateTime? expiresAt;
  final String? batchId;
  final String? note;
}

String _formatQuantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}
