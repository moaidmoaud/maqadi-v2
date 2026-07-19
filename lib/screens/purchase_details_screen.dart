import 'package:flutter/material.dart';

import '../models/purchase_models.dart';
import '../services/purchase_service.dart';
import 'purchase_form_screen.dart';

class PurchaseDetailsScreen extends StatefulWidget {
  const PurchaseDetailsScreen({
    super.key,
    required this.service,
    required this.purchaseId,
  });

  final PurchaseService service;
  final String purchaseId;

  @override
  State<PurchaseDetailsScreen> createState() => _PurchaseDetailsScreenState();
}

class _PurchaseDetailsScreenState extends State<PurchaseDetailsScreen> {
  PurchaseDetails? _details;
  Object? _error;
  bool _loading = true;
  bool _deleting = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final details = await widget.service.readPurchaseWithDetails(
        widget.purchaseId,
      );
      if (!mounted) return;
      setState(() {
        _details = details;
        _error = details == null ? StateError('عملية الشراء غير موجودة') : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _edit() async {
    final details = _details;
    if (details == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: PurchaseFormScreen(
            service: widget.service,
            initialPurchase: details.purchase,
            initialItems: details.items,
          ),
        ),
      ),
    );
    if (changed == true && mounted) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف عملية الشراء؟'),
        content: const Text(
          'سيتم حذف العملية وعكس كميات المخزون المرتبطة بها. لا يمكن التراجع عن ذلك.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-purchase'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.service.deletePurchaseSafely(widget.purchaseId);
      if (mounted) Navigator.pop(context, true);
    } on PurchaseDeletionException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حذف عملية الشراء: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<bool> _handleBack() async {
    Navigator.pop(context, _changed);
    return false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_changed,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _changed) _handleBack();
        },
        child: Scaffold(
          key: const ValueKey('purchase-details-screen'),
          appBar: AppBar(
            title: const Text('تفاصيل الشراء'),
            actions: [
              IconButton(
                key: const ValueKey('edit-purchase'),
                tooltip: 'تعديل',
                onPressed: _loading || _details == null ? null : _edit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: const ValueKey('delete-purchase'),
                tooltip: 'حذف',
                onPressed:
                    _loading || _details == null || _deleting ? null : _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: _buildBody(),
        ),
      );

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تعذر تحميل التفاصيل: $_error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _load,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    final details = _details!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _PurchaseInformationCard(purchase: details.purchase),
        const SizedBox(height: 14),
        Text(
          'المنتجات (${details.items.length})',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        for (final item in details.items) ...[
          _PurchaseItemCard(
            item: item,
            productName: widget.service.productNameFor(item.productId),
          ),
          const SizedBox(height: 8),
        ],
        if (_deleting) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

class _PurchaseInformationCard extends StatelessWidget {
  const _PurchaseInformationCard({required this.purchase});

  final Purchase purchase;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _DetailRow(label: 'المتجر', value: purchase.storeId),
              _DetailRow(
                label: 'تاريخ الشراء',
                value: _formatDate(purchase.purchaseDate),
              ),
              if (purchase.notes case final notes?)
                _DetailRow(label: 'ملاحظات', value: notes),
              const Divider(),
              _MoneyRow(label: 'الإجمالي الفرعي', value: purchase.subtotal),
              _MoneyRow(label: 'الخصم', value: purchase.discount),
              _MoneyRow(label: 'الضريبة', value: purchase.tax),
              const Divider(),
              _MoneyRow(
                  label: 'الإجمالي', value: purchase.total, emphasized: true),
            ],
          ),
        ),
      );
}

class _PurchaseItemCard extends StatelessWidget {
  const _PurchaseItemCard({required this.item, required this.productName});

  final PurchaseItem item;
  final String productName;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _DetailRow(label: 'المنتج', value: productName),
              _DetailRow(label: 'الكمية', value: _number(item.quantity)),
              _MoneyRow(label: 'سعر الوحدة', value: item.unitPrice),
              _MoneyRow(
                  label: 'السعر النهائي للوحدة', value: item.finalUnitPrice),
              _MoneyRow(label: 'إجمالي السطر', value: item.lineTotal),
              if (item.expiryDate case final expiry?)
                _DetailRow(label: 'تاريخ الانتهاء', value: _formatDate(expiry)),
              if (item.batchId case final batchId?)
                _DetailRow(label: 'الدفعة المرتبطة', value: batchId),
            ],
          ),
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final double value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
        style: emphasized
            ? const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)
            : null,
        child:
            _DetailRow(label: label, value: '${value.toStringAsFixed(2)} ر.س'),
      );
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String _formatDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
