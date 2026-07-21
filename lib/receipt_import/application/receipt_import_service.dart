import '../../product_matching/domain/product_match_models.dart';
import '../../product_matching/engine/text_normalizer.dart';
import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import '../domain/receipt_draft.dart';
import '../domain/receipt_import_failure.dart';
import 'receipt_purchase_gateway.dart';

typedef ReceiptImportClock = DateTime Function();

class ReceiptImportService {
  ReceiptImportService({
    required ReceiptPurchaseGateway purchaseGateway,
    ReceiptImportClock? clock,
    TextNormalizer normalizer = const TextNormalizer(),
  })  : _purchaseGateway = purchaseGateway,
        _clock = clock ?? DateTime.now,
        _normalizer = normalizer;

  final ReceiptPurchaseGateway _purchaseGateway;
  final ReceiptImportClock _clock;
  final TextNormalizer _normalizer;
  int _idCounter = 0;

  Future<ReceiptDraftReview> prepareReview({
    required ReceiptOcrResult ocrResult,
    required ProductMatchResult matchResult,
  }) async {
    final sourceLines = _sourceLines(ocrResult);
    if (sourceLines.isEmpty) {
      throw const InvalidReceiptDraft('نتيجة OCR لا تحتوي على أسطر صالحة.');
    }
    try {
      final products = _purchaseGateway.receiptImportProducts();
      final stores = await _purchaseGateway.receiptImportStores();
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
    } on ReceiptPurchaseGatewayException catch (error) {
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
    _item(draft, itemId).quantity = quantity;
    _markModified(draft);
  }

  void updateUnitPrice(ReceiptDraft draft, String itemId, double unitPrice) {
    _item(draft, itemId).unitPrice = unitPrice;
    _markModified(draft);
  }

  void updateMetadata(
    ReceiptDraft draft, {
    String? storeId,
    DateTime? purchaseDate,
    String? notes,
  }) {
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
    draft
      ..discount = discount
      ..tax = tax;
    _markModified(draft);
  }

  void removeItem(ReceiptDraft draft, String itemId) {
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
        .receiptImportProducts()
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

  Future<ReceiptImportConfirmation> confirm(ReceiptDraft draft) async {
    if (draft.isCancelled) throw const ReceiptImportCancelled();
    final errors = validate(draft);
    if (errors.isNotEmpty) throw ReceiptDraftValidationFailed(errors);
    try {
      return await _purchaseGateway.createPurchaseFromReceiptDraft(draft);
    } on ReceiptPurchaseGatewayException catch (error) {
      throw _mapGatewayFailure(error);
    } on ReceiptImportFailure {
      rethrow;
    } catch (error) {
      throw ReceiptPurchaseCreationFailed(
        'تعذر إنشاء عملية الشراء من الإيصال.',
        cause: error,
      );
    }
  }

  void cancel(ReceiptDraft draft) {
    draft
      ..isCancelled = true
      ..hasUserModifications = true;
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

  ReceiptImportFailure _mapGatewayFailure(
    ReceiptPurchaseGatewayException error,
  ) =>
      switch (error.code) {
        ReceiptPurchaseGatewayErrorCode.validation =>
          ReceiptDraftValidationFailed([error.message]),
        ReceiptPurchaseGatewayErrorCode.repository =>
          ReceiptImportRepositoryFailure(error.message, cause: error.cause),
        ReceiptPurchaseGatewayErrorCode.creation =>
          ReceiptPurchaseCreationFailed(error.message, cause: error.cause),
      };

  String _newId(String prefix) {
    _idCounter++;
    return '${prefix}_${_clock().microsecondsSinceEpoch}_$_idCounter';
  }
}
