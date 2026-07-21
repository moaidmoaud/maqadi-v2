import 'package:flutter/material.dart';

import '../../product_matching/domain/product_match_models.dart';
import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import '../application/receipt_import_service.dart';
import '../domain/receipt_draft.dart';
import '../domain/receipt_import_failure.dart';

enum ReceiptReviewViewStatus { loading, review, error }

class ReceiptReviewScreen extends StatefulWidget {
  const ReceiptReviewScreen({
    super.key,
    required this.service,
    required this.ocrResult,
    required this.matchResult,
    this.onConfirmed,
  });

  final ReceiptImportService service;
  final ReceiptOcrResult ocrResult;
  final ProductMatchResult matchResult;
  final ValueChanged<ReceiptImportConfirmation>? onConfirmed;

  @override
  State<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends State<ReceiptReviewScreen> {
  ReceiptReviewViewStatus _status = ReceiptReviewViewStatus.loading;
  ReceiptDraftReview? _review;
  String? _errorMessage;
  List<String> _validationErrors = const [];
  bool _confirming = false;
  final Map<String, _DraftItemControllers> _controllers = {};
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final controllers in _controllers.values) {
      controllers.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _status = ReceiptReviewViewStatus.loading;
      _errorMessage = null;
    });
    try {
      final review = await widget.service.prepareReview(
        ocrResult: widget.ocrResult,
        matchResult: widget.matchResult,
      );
      if (!mounted) return;
      _syncControllers(review.draft);
      _notesController.text = review.draft.metadata.notes ?? '';
      setState(() {
        _review = review;
        _status = ReceiptReviewViewStatus.review;
      });
    } on ReceiptImportFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _errorMessage = failure.message;
        _status = ReceiptReviewViewStatus.error;
      });
    }
  }

  void _syncControllers(ReceiptDraft draft) {
    final activeIds = draft.items.map((item) => item.id).toSet();
    for (final id in _controllers.keys.toList()) {
      if (!activeIds.contains(id)) _controllers.remove(id)?.dispose();
    }
    for (final item in draft.items) {
      _controllers.putIfAbsent(
        item.id,
        () => _DraftItemControllers(item),
      );
    }
  }

  Future<ReceiptDraftProductOption?> _pickProduct() =>
      showModalBottomSheet<ReceiptDraftProductOption>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _ReceiptProductPicker(
          review: _review!,
          service: widget.service,
        ),
      );

  Future<void> _replaceProduct(ReceiptDraftItem item) async {
    final product = await _pickProduct();
    if (product == null || !mounted) return;
    setState(() {
      widget.service.selectProduct(_review!.draft, item.id, product);
      _validationErrors = const [];
    });
  }

  Future<void> _addLine([String? sourceText]) async {
    final product = await _pickProduct();
    if (product == null || !mounted) return;
    setState(() {
      widget.service.addItem(
        _review!.draft,
        product: product,
        sourceText: sourceText ?? 'بند مضاف يدويًا',
      );
      _syncControllers(_review!.draft);
      _validationErrors = const [];
    });
  }

  void _remove(ReceiptDraftItem item) {
    setState(() {
      widget.service.removeItem(_review!.draft, item.id);
      _syncControllers(_review!.draft);
      _validationErrors = const [];
    });
  }

  void _updateNumber(ReceiptDraftItem item, {required bool quantity}) {
    final controllers = _controllers[item.id]!;
    final text =
        quantity ? controllers.quantity.text : controllers.unitPrice.text;
    final value = double.tryParse(text.trim()) ?? double.nan;
    setState(() {
      if (quantity) {
        widget.service.updateQuantity(_review!.draft, item.id, value);
      } else {
        widget.service.updateUnitPrice(_review!.draft, item.id, value);
      }
      _validationErrors = const [];
    });
  }

  Future<void> _confirm() async {
    final draft = _review!.draft;
    widget.service.updateMetadata(draft, notes: _notesController.text);
    final errors = widget.service.validate(draft);
    if (errors.isNotEmpty) {
      setState(() => _validationErrors = errors);
      return;
    }
    setState(() {
      _confirming = true;
      _validationErrors = const [];
    });
    try {
      final confirmation = await widget.service.confirm(draft);
      if (!mounted) return;
      widget.onConfirmed?.call(confirmation);
      if (widget.onConfirmed == null) Navigator.pop(context, confirmation);
    } on ReceiptDraftValidationFailed catch (failure) {
      if (!mounted) return;
      setState(() => _validationErrors = failure.errors);
    } on ReceiptImportFailure catch (failure) {
      if (!mounted) return;
      setState(() => _validationErrors = [failure.message]);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _cancel() {
    final review = _review;
    if (review != null) widget.service.cancel(review.draft);
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('receipt-review-screen'),
        appBar: AppBar(
          title: const Text('مراجعة الإيصال'),
          leading: IconButton(
            key: const ValueKey('receipt-import-cancel'),
            tooltip: 'إلغاء الاستيراد',
            onPressed: _cancel,
            icon: const Icon(Icons.close),
          ),
        ),
        body: SafeArea(child: _buildBody()),
        bottomNavigationBar: _status == ReceiptReviewViewStatus.review
            ? SafeArea(
                minimum: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  key: const ValueKey('confirm-receipt-import'),
                  onPressed: _confirming ? null : _confirm,
                  icon: _confirming
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('تأكيد الاستيراد'),
                ),
              )
            : null,
      );

  Widget _buildBody() => switch (_status) {
        ReceiptReviewViewStatus.loading => const _ReceiptReviewLoading(),
        ReceiptReviewViewStatus.error => _ReceiptReviewError(
            message: _errorMessage!,
            onRetry: _load,
          ),
        ReceiptReviewViewStatus.review => _buildReview(),
      };

  Widget _buildReview() {
    final review = _review!;
    final draft = review.draft;
    return ListView(
      key: const ValueKey('receipt-review-content'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _ReceiptMetadataCard(
          draft: draft,
          stores: review.stores,
          notesController: _notesController,
          onStoreChanged: (storeId) => setState(() {
            widget.service.updateMetadata(draft, storeId: storeId);
            _validationErrors = const [];
          }),
          onDateChanged: (date) => setState(() {
            widget.service.updateMetadata(draft, purchaseDate: date);
          }),
        ),
        if (_validationErrors.isNotEmpty) ...[
          const SizedBox(height: 8),
          _ValidationCard(errors: _validationErrors),
        ],
        if (draft.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          _WarningCard(warnings: draft.warnings),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'بنود الإيصال',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('add-receipt-line'),
              onPressed: review.products.isEmpty ? null : _addLine,
              icon: const Icon(Icons.add),
              label: const Text('إضافة بند'),
            ),
          ],
        ),
        if (draft.items.isEmpty)
          const Card(
            key: ValueKey('receipt-draft-empty'),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('لا توجد بنود مطابقة. أضف المنتجات يدويًا.'),
            ),
          ),
        for (final item in draft.items) ...[
          _ReceiptDraftItemCard(
            key: ValueKey('receipt-draft-item-${item.id}'),
            item: item,
            controllers: _controllers[item.id]!,
            onQuantityChanged: () => _updateNumber(item, quantity: true),
            onPriceChanged: () => _updateNumber(item, quantity: false),
            onReplace: () => _replaceProduct(item),
            onCandidateSelected: (candidate) => setState(() {
              widget.service.selectCandidate(draft, item.id, candidate);
            }),
            onRemove: () => _remove(item),
          ),
          const SizedBox(height: 8),
        ],
        if (draft.unmatchedLines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('أسطر غير مطابقة',
              style: Theme.of(context).textTheme.titleMedium),
          for (final line in draft.unmatchedLines.toList())
            ListTile(
              title: Text(line),
              trailing: TextButton.icon(
                key: ValueKey('add-unmatched-${line.hashCode}'),
                onPressed:
                    review.products.isEmpty ? null : () => _addLine(line),
                icon: const Icon(Icons.add),
                label: const Text('إضافة'),
              ),
            ),
        ],
        const SizedBox(height: 8),
        _ReceiptTotalsCard(totals: draft.totals),
      ],
    );
  }
}

class _ReceiptMetadataCard extends StatelessWidget {
  const _ReceiptMetadataCard({
    required this.draft,
    required this.stores,
    required this.notesController,
    required this.onStoreChanged,
    required this.onDateChanged,
  });

  final ReceiptDraft draft;
  final List<ReceiptDraftStoreOption> stores;
  final TextEditingController notesController;
  final ValueChanged<String> onStoreChanged;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                key: const ValueKey('receipt-import-store'),
                initialValue: draft.metadata.storeId,
                decoration: const InputDecoration(
                  labelText: 'المتجر *',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final store in stores)
                    DropdownMenuItem(value: store.id, child: Text(store.name)),
                ],
                onChanged: (value) {
                  if (value != null) onStoreChanged(value);
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const ValueKey('receipt-import-date'),
                onPressed: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: draft.metadata.purchaseDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (selected != null) onDateChanged(selected);
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_formatDate(draft.metadata.purchaseDate)),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('receipt-import-notes'),
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

class _ReceiptDraftItemCard extends StatelessWidget {
  const _ReceiptDraftItemCard({
    super.key,
    required this.item,
    required this.controllers,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onReplace,
    required this.onCandidateSelected,
    required this.onRemove,
  });

  final ReceiptDraftItem item;
  final _DraftItemControllers controllers;
  final VoidCallback onQuantityChanged;
  final VoidCallback onPriceChanged;
  final VoidCallback onReplace;
  final ValueChanged<ReceiptDraftProductCandidate> onCandidateSelected;
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
                      item.productName ?? 'منتج غير محدد',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: ValueKey('remove-receipt-item-${item.id}'),
                    tooltip: 'إزالة البند',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              Text('النص: ${item.sourceText}'),
              if (item.candidates.length > 1) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final candidate in item.candidates)
                      ChoiceChip(
                        label: Text(candidate.productName),
                        selected: item.productId == candidate.productId,
                        onSelected: (_) => onCandidateSelected(candidate),
                      ),
                  ],
                ),
              ],
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: ValueKey('replace-receipt-product-${item.id}'),
                  onPressed: onReplace,
                  icon: const Icon(Icons.search),
                  label: const Text('بحث واختيار منتج آخر'),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: ValueKey('receipt-quantity-${item.id}'),
                      controller: controllers.quantity,
                      onChanged: (_) => onQuantityChanged(),
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
                      key: ValueKey('receipt-price-${item.id}'),
                      controller: controllers.unitPrice,
                      onChanged: (_) => onPriceChanged(),
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
            ],
          ),
        ),
      );
}

class _ReceiptProductPicker extends StatefulWidget {
  const _ReceiptProductPicker({required this.review, required this.service});

  final ReceiptDraftReview review;
  final ReceiptImportService service;

  @override
  State<_ReceiptProductPicker> createState() => _ReceiptProductPickerState();
}

class _ReceiptProductPickerState extends State<_ReceiptProductPicker> {
  late List<ReceiptDraftProductOption> _products = widget.review.products;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('receipt-product-search'),
                  autofocus: true,
                  onChanged: (query) => setState(() {
                    _products = widget.service.searchProducts(
                      widget.review,
                      query,
                    );
                  }),
                  decoration: const InputDecoration(
                    labelText: 'بحث عن منتج',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                Expanded(
                  child: _products.isEmpty
                      ? const Center(child: Text('لا توجد منتجات مطابقة.'))
                      : ListView.builder(
                          key: const ValueKey('receipt-product-results'),
                          itemCount: _products.length,
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            return ListTile(
                              key: ValueKey(
                                'select-receipt-product-${product.id}',
                              ),
                              title: Text(product.name),
                              subtitle: Text(
                                '${product.category} • ${product.unit}',
                              ),
                              onTap: () => Navigator.pop(context, product),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('receipt-import-validation'),
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final error in errors) Text('• $error')],
          ),
        ),
      );
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.warnings});

  final List<ReceiptDraftWarning> warnings;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('receipt-draft-warnings'),
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تنبيهات المراجعة',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final warning in warnings) Text('• ${warning.message}'),
            ],
          ),
        ),
      );
}

class _ReceiptTotalsCard extends StatelessWidget {
  const _ReceiptTotalsCard({required this.totals});

  final ReceiptDraftTotals totals;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('receipt-draft-totals'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _totalRow('الإجمالي الفرعي', totals.subtotal),
              _totalRow('الخصم', totals.discount),
              _totalRow('الضريبة', totals.tax),
              const Divider(),
              _totalRow('الإجمالي', totals.total, emphasized: true),
            ],
          ),
        ),
      );

  Widget _totalRow(String label, double value, {bool emphasized = false}) =>
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasized
                  ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
                  : null,
            ),
          ),
          Text(
            value.isFinite ? value.toStringAsFixed(2) : '—',
            style: emphasized
                ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
                : null,
          ),
        ],
      );
}

class _ReceiptReviewLoading extends StatelessWidget {
  const _ReceiptReviewLoading();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جارٍ تجهيز مسودة الإيصال...'),
          ],
        ),
      );
}

class _ReceiptReviewError extends StatelessWidget {
  const _ReceiptReviewError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        key: const ValueKey('receipt-review-error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('receipt-review-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}

class _DraftItemControllers {
  _DraftItemControllers(ReceiptDraftItem item)
      : quantity = TextEditingController(text: _numberText(item.quantity)),
        unitPrice = TextEditingController(text: _numberText(item.unitPrice));

  final TextEditingController quantity;
  final TextEditingController unitPrice;

  void dispose() {
    quantity.dispose();
    unitPrice.dispose();
  }
}

String _numberText(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _formatDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
