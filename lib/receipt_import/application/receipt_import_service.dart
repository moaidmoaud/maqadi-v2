import '../../product_matching/domain/product_match_models.dart';
import '../../product_matching/engine/text_normalizer.dart';
import '../../purchase/application/purchase_creation_gateway.dart';
import '../../purchase/domain/purchase_creation_command.dart';
import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import '../domain/receipt_draft.dart';
import '../domain/receipt_import_failure.dart';

typedef ReceiptImportClock = DateTime Function();

class ReceiptImportService {
  ReceiptImportService({
    required PurchaseCreationGateway purchaseGateway,
    ReceiptImportClock? clock,
    TextNormalizer normalizer = const TextNormalizer(),
  })  : _purchaseGateway = purchaseGateway,
        _clock = clock ?? DateTime.now,
        _normalizer = normalizer;

  final PurchaseCreationGateway _purchaseGateway;
  final ReceiptImportClock _clock;
  final TextNormalizer _normalizer;
  int _idCounter = 0;
  final Map<String, Future<ReceiptImportConfirmation>> _confirmations = {};

  Future<ReceiptDraftReview> prepareReview({
    required ReceiptOcrResult ocrResult,
    required ProductMatchResult matchResult,
  }) async {
    final sourceLines = _sourceLines(ocrResult);
    if (sourceLines.isEmpty) {
      throw const InvalidReceiptDraft('نتيجة OCR لا تحتوي على أسطر صالحة.');
    }
    try {
      final products = _purchaseGateway
          .purchaseCreationProducts()
          .map(
            (product) => ReceiptDraftProductOption(
              id: product.id,
              name: product.name,
              category: product.category,
              unit: product.unit,
            ),
          )
          .toList(growable: false);
      final stores = (await _purchaseGateway.purchaseCreationStores())
          .where((store) => store.isActive)
          .map(
            (store) => ReceiptDraftStoreOption(id: store.id, name: store.name),
          )
          .toList(growable: false);
      final productByName = {
        for (final product in products)
          _normalizer.normalize(product.name): product,
      };
      final matchesByLine = <String, List<MatchedProduct>>{};
      for (final match in matchResult.matches) {
        matchesByLine
            .putIfAbsent(
              _normalizer.normalize(match.matchedText),
              () => <MatchedProduct>[],
            )
            .add(match);
      }
      final items = <ReceiptDraftItem>[];
      final unmatched = <String>[];
      for (final line in sourceLines) {
        final matches = matchesByLine[_normalizer.normalize(line)] ?? const [];
        final candidates = <ReceiptDraftProductCandidate>[];
        final candidateIds = <String>{};
        for (final match in matches) {
          final product =
              productByName[_normalizer.normalize(match.product.name)];
          if (product == null || !candidateIds.add(product.id)) continue;
          candidates.add(
            ReceiptDraftProductCandidate(
              productId: product.id,
              productName: product.name,
              category: product.category,
              confidence: match.confidence.value,
              strategy: match.matchedStrategy,
              matchedText: match.matchedText,
            ),
          );
        }
        candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
        if (candidates.isEmpty) {
          unmatched.add(line);
          continue;
        }
        final selected = candidates.first;
        items.add(
          ReceiptDraftItem(
            id: _newId('receipt-line'),
            sourceText: line,
            productId: selected.productId,
            productName: selected.productName,
            quantity: 1,
            unitPrice: 0,
            candidates: candidates,
          ),
        );
      }
      final now = _clock();
      final draft = ReceiptDraft(
        id: _newId('receipt-draft'),
        metadata: ReceiptDraftMetadata(
          createdAt: now,
          purchaseDate: now,
          sourceLineCount: sourceLines.length,
        ),
        items: items,
        unmatchedLines: unmatched,
      );
      _refresh(draft);
      return ReceiptDraftReview(
        draft: draft,
        products: List.unmodifiable(products),
        stores: List.unmodifiable(stores),
      );
    } on PurchaseCreationException catch (error) {
      throw _mapGatewayFailure(error);
    } on ReceiptImportFailure {
      rethrow;
    } catch (error) {
      throw ReceiptImportRepositoryFailure(
        'تعذر تجهيز بيانات مراجعة الإيصال.',
        cause: error,
      );
    }
  }

  void selectProduct(
    ReceiptDraft draft,
    String itemId,
    ReceiptDraftProductOption product,
  ) {
    _ensureEditable(draft);
    final item = _item(draft, itemId);
    item
      ..productId = product.id
      ..productName = product.name;
    _markModified(draft);
  }

  void selectCandidate(
    ReceiptDraft draft,
    String itemId,
    ReceiptDraftProductCandidate candidate,
  ) {
    _ensureEditable(draft);
    final item = _item(draft, itemId);
    item
      ..productId = candidate.productId
      ..productName = candidate.productName;
    _markModified(draft);
  }

  List<ReceiptDraftProductOption> searchProducts(
    ReceiptDraftReview review,
    String query,
  ) {
    final normalized = _normalizer.normalize(query);
    if (normalized.isEmpty) return review.products;
    return List.unmodifiable(
      review.products.where(
        (product) =>
            _normalizer.normalize(product.name).contains(normalized) ||
            _normalizer.normalize(product.category).contains(normalized),
      ),
    );
  }

  void updateQuantity(ReceiptDraft draft, String itemId, double quantity) {
    _ensureEditable(draft);
    _item(draft, itemId).quantity = quantity;
    _markModified(draft);
  }

  void updateUnitPrice(ReceiptDraft draft, String itemId, double unitPrice) {
    _ensureEditable(draft);
    _item(draft, itemId).unitPrice = unitPrice;
    _markModified(draft);
  }

  void updateMetadata(
    ReceiptDraft draft, {
    String? storeId,
    DateTime? purchaseDate,
    String? notes,
  }) {
    _ensureEditable(draft);
    if (storeId != null) draft.metadata.storeId = _clean(storeId);
    if (purchaseDate != null) draft.metadata.purchaseDate = purchaseDate;
    if (notes != null) draft.metadata.notes = _clean(notes);
    _markModified(draft);
  }

  void updateAdjustments(
    ReceiptDraft draft, {
    required double discount,
    required double tax,
  }) {
    _ensureEditable(draft);
    draft
      ..discount = discount
      ..tax = tax;
    _markModified(draft);
  }

  void removeItem(ReceiptDraft draft, String itemId) {
    _ensureEditable(draft);
    final index = draft.items.indexWhere((item) => item.id == itemId);
    if (index < 0) throw const InvalidReceiptDraft('بند الإيصال غير موجود.');
    final removed = draft.items.removeAt(index);
    if (removed.sourceText.trim().isNotEmpty &&
        !draft.unmatchedLines.contains(removed.sourceText)) {
      draft.unmatchedLines.add(removed.sourceText);
    }
    _markModified(draft);
  }

  ReceiptDraftItem addItem(
    ReceiptDraft draft, {
    required ReceiptDraftProductOption product,
    String sourceText = 'بند مضاف يدويًا',
    double quantity = 1,
    double unitPrice = 0,
  }) {
    _ensureEditable(draft);
    final item = ReceiptDraftItem(
      id: _newId('receipt-line'),
      sourceText: sourceText.trim().isEmpty ? 'بند مضاف يدويًا' : sourceText,
      productId: product.id,
      productName: product.name,
      quantity: quantity,
      unitPrice: unitPrice,
    );
    draft.items.add(item);
    draft.unmatchedLines.remove(sourceText);
    _markModified(draft);
    return item;
  }

  List<String> validate(ReceiptDraft draft) {
    final errors = <String>[];
    if (draft.id.trim().isEmpty) errors.add('معرّف المسودة مطلوب.');
    if (draft.metadata.storeId?.trim().isEmpty ?? true) {
      errors.add('اختر المتجر.');
    }
    if (draft.items.isEmpty) errors.add('أضف منتجًا واحدًا على الأقل.');
    final availableIds = _purchaseGateway
        .purchaseCreationProducts()
        .map((product) => product.id)
        .toSet();
    for (var index = 0; index < draft.items.length; index++) {
      final item = draft.items[index];
      final label = item.productName ?? 'البند ${index + 1}';
      if (item.productId == null || !availableIds.contains(item.productId)) {
        errors.add('اختر منتجًا صالحًا للبند: $label.');
      }
      if (!item.quantity.isFinite || item.quantity <= 0) {
        errors.add('كمية $label يجب أن تكون أكبر من صفر.');
      }
      if (!item.unitPrice.isFinite || item.unitPrice < 0) {
        errors.add('سعر $label غير صالح.');
      }
    }
    final subtotal = _subtotal(draft.items);
    if (!draft.discount.isFinite ||
        draft.discount < 0 ||
        draft.discount > subtotal) {
      errors.add('الخصم يجب أن يكون بين صفر والإجمالي الفرعي.');
    }
    if (!draft.tax.isFinite || draft.tax < 0) {
      errors.add('الضريبة يجب ألا تكون سالبة.');
    }
    return List.unmodifiable(errors);
  }

  Future<ReceiptImportConfirmation> confirm(ReceiptDraft draft) {
    final completed = draft.confirmation;
    if (draft.confirmationStatus == ReceiptDraftConfirmationStatus.confirmed &&
        completed != null) {
      return Future.value(completed);
    }
    if (draft.isCancelled) {
      return Future.error(const ReceiptImportCancelled());
    }
    final active = _confirmations[draft.id];
    if (active != null) return active;
    final errors = validate(draft);
    if (errors.isNotEmpty) {
      return Future.error(ReceiptDraftValidationFailed(errors));
    }
    draft.confirmationStatus = ReceiptDraftConfirmationStatus.confirming;
    late final Future<ReceiptImportConfirmation> operation;
    operation = _confirm(draft).whenComplete(() {
      if (identical(_confirmations[draft.id], operation)) {
        _confirmations.remove(draft.id);
      }
    });
    _confirmations[draft.id] = operation;
    return operation;
  }

  Future<ReceiptImportConfirmation> _confirm(ReceiptDraft draft) async {
    try {
      final result = await _purchaseGateway.createFromCommand(
        PurchaseCreationCommand(
          requestId: draft.id,
          storeId: draft.metadata.storeId ?? '',
          purchaseDate: draft.metadata.purchaseDate,
          items: [
            for (final item in draft.items)
              PurchaseCreationItem(
                productId: item.productId ?? '',
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                expiryDate: item.expiryDate,
              ),
          ],
          discount: draft.discount,
          tax: draft.tax,
          notes: draft.metadata.notes,
        ),
      );
      final confirmation = ReceiptImportConfirmation(
        purchaseId: result.purchaseId,
        total: result.total,
        purchaseDate: result.purchaseDate,
      );
      draft
        ..confirmation = confirmation
        ..confirmationStatus = ReceiptDraftConfirmationStatus.confirmed;
      return confirmation;
    } on PurchaseCreationException catch (error) {
      draft.confirmationStatus = ReceiptDraftConfirmationStatus.failed;
      throw _mapGatewayFailure(error);
    } on ReceiptImportFailure {
      draft.confirmationStatus = ReceiptDraftConfirmationStatus.failed;
      rethrow;
    } catch (error) {
      draft.confirmationStatus = ReceiptDraftConfirmationStatus.failed;
      throw ReceiptPurchaseCreationFailed(
        'تعذر إنشاء عملية الشراء من الإيصال.',
        cause: error,
      );
    }
  }

  bool cancel(ReceiptDraft draft) {
    if (draft.confirmationStatus == ReceiptDraftConfirmationStatus.confirming ||
        draft.confirmationStatus == ReceiptDraftConfirmationStatus.confirmed) {
      return false;
    }
    draft
      ..confirmationStatus = ReceiptDraftConfirmationStatus.cancelled
      ..hasUserModifications = true;
    return true;
  }

  void _ensureEditable(ReceiptDraft draft) {
    if (draft.confirmationStatus != ReceiptDraftConfirmationStatus.ready &&
        draft.confirmationStatus != ReceiptDraftConfirmationStatus.failed) {
      throw const InvalidReceiptDraft(
        'لا يمكن تعديل مسودة الإيصال في حالتها الحالية.',
      );
    }
  }

  ReceiptDraftItem _item(ReceiptDraft draft, String itemId) {
    for (final item in draft.items) {
      if (item.id == itemId) return item;
    }
    throw const InvalidReceiptDraft('بند الإيصال غير موجود.');
  }

  void _markModified(ReceiptDraft draft) {
    draft.hasUserModifications = true;
    _refresh(draft);
  }

  void _refresh(ReceiptDraft draft) {
    final subtotal = _subtotal(draft.items);
    final total = subtotal - draft.discount + draft.tax;
    draft.totals = ReceiptDraftTotals(
      subtotal: _money(subtotal),
      discount: _money(draft.discount),
      tax: _money(draft.tax),
      total: _money(total),
    );
    draft.warnings
      ..clear()
      ..addAll(
        draft.unmatchedLines.map(
          (line) => ReceiptDraftWarning(
            type: ReceiptDraftWarningType.unmatchedLine,
            message: 'لم تتم مطابقة السطر: $line',
            sourceText: line,
          ),
        ),
      );
    for (final item in draft.items) {
      if (item.productId == null) {
        draft.warnings.add(
          ReceiptDraftWarning(
            type: ReceiptDraftWarningType.missingProduct,
            message: 'اختر منتجًا للسطر: ${item.sourceText}',
            itemId: item.id,
            sourceText: item.sourceText,
          ),
        );
      }
      if (item.candidates.isNotEmpty &&
          item.candidates.first.confidence < 0.75) {
        draft.warnings.add(
          ReceiptDraftWarning(
            type: ReceiptDraftWarningType.lowConfidence,
            message:
                'راجع مطابقة المنتج: ${item.productName ?? item.sourceText}',
            itemId: item.id,
          ),
        );
      }
      if (item.unitPrice == 0) {
        draft.warnings.add(
          ReceiptDraftWarning(
            type: ReceiptDraftWarningType.zeroPrice,
            message: 'راجع سعر ${item.productName ?? item.sourceText}.',
            itemId: item.id,
          ),
        );
      }
    }
  }

  List<String> _sourceLines(ReceiptOcrResult result) {
    final structured = <String>[
      for (final block in result.blocks)
        for (final line in block.lines) line.text,
    ];
    final source =
        structured.isEmpty ? result.text.split(RegExp(r'\r?\n')) : structured;
    final seen = <String>{};
    return [
      for (final line in source)
        if (line.trim().isNotEmpty && seen.add(_normalizer.normalize(line)))
          line.trim(),
    ];
  }

  double _subtotal(Iterable<ReceiptDraftItem> items) => items.fold<double>(
        0,
        (total, item) => total + item.quantity * item.unitPrice,
      );

  double _money(double value) =>
      value.isFinite ? (value * 100).round() / 100 : value;

  String? _clean(String value) {
    final clean = value.trim();
    return clean.isEmpty ? null : clean;
  }

  ReceiptImportFailure _mapGatewayFailure(PurchaseCreationException error) =>
      switch (error.code) {
        PurchaseCreationErrorCode.validation => ReceiptDraftValidationFailed([
            error.message,
          ]),
        PurchaseCreationErrorCode.repository => ReceiptImportRepositoryFailure(
            error.message,
            cause: error.cause,
          ),
        PurchaseCreationErrorCode.creation => ReceiptPurchaseCreationFailed(
            error.message,
            cause: error.cause,
          ),
      };

  String _newId(String prefix) {
    _idCounter++;
    return '${prefix}_${_clock().microsecondsSinceEpoch}_$_idCounter';
  }
}
