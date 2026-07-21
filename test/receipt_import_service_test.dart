import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/product_matching/domain/product_match_models.dart';
import 'package:maqadi_v2/receipt_import/application/receipt_import_service.dart';
import 'package:maqadi_v2/receipt_import/application/receipt_purchase_gateway.dart';
import 'package:maqadi_v2/receipt_import/domain/receipt_draft.dart';
import 'package:maqadi_v2/receipt_import/domain/receipt_import_failure.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/repositories/purchase_repository.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/purchase_service.dart';

void main() {
  group('ReceiptImportService', () {
    late _MockReceiptPurchaseGateway gateway;
    late ReceiptImportService service;

    setUp(() {
      gateway = _MockReceiptPurchaseGateway();
      service = ReceiptImportService(
        purchaseGateway: gateway,
        clock: () => DateTime.utc(2026, 7, 21, 10),
      );
    });

    test('creates an editable draft from OCR and matching results', () async {
      final review = await service.prepareReview(
        ocrResult: _ocr(['Milk', 'Receipt total']),
        matchResult: _matches([_match('Milk', 'Milk')]),
      );

      expect(review.draft.items, hasLength(1));
      expect(review.draft.items.single.productId, 'milk');
      expect(review.draft.items.single.quantity, 1);
      expect(review.draft.items.single.unitPrice, 0);
      expect(review.draft.unmatchedLines, ['Receipt total']);
      expect(review.draft.metadata.sourceLineCount, 2);
      expect(review.products, gateway.products);
      expect(review.stores, gateway.stores);
      expect(review.draft.hasUserModifications, isFalse);
    });

    test('draft quantity and price editing recalculates totals', () async {
      final review = await _review(service);
      final item = review.draft.items.single;

      service.updateQuantity(review.draft, item.id, 3);
      service.updateUnitPrice(review.draft, item.id, 4.5);

      expect(item.quantity, 3);
      expect(item.unitPrice, 4.5);
      expect(review.draft.totals.subtotal, 13.5);
      expect(review.draft.totals.total, 13.5);
      expect(review.draft.hasUserModifications, isTrue);
    });

    test('manual product replacement updates only the draft', () async {
      final review = await _review(service);
      final item = review.draft.items.single;

      service.selectProduct(review.draft, item.id, gateway.products.last);

      expect(item.productId, 'bread');
      expect(item.productName, 'Brown Bread');
      expect(gateway.createCalls, 0);
    });

    test('candidate replacement uses the candidate selected by the user',
        () async {
      final review = await service.prepareReview(
        ocrResult: _ocr(['Milk']),
        matchResult: _matches([
          _match('Milk', 'Milk', confidence: 0.9),
          _match('Milk', 'Brown Bread', confidence: 0.8),
        ]),
      );
      final item = review.draft.items.single;

      service.selectCandidate(review.draft, item.id, item.candidates.last);

      expect(item.productId, 'bread');
      expect(item.productName, 'Brown Bread');
    });

    test('line removal preserves its OCR text as unmatched', () async {
      final review = await _review(service);
      final item = review.draft.items.single;

      service.removeItem(review.draft, item.id);

      expect(review.draft.items, isEmpty);
      expect(review.draft.unmatchedLines, contains('Milk'));
      expect(
        review.draft.warnings.map((warning) => warning.type),
        contains(ReceiptDraftWarningType.unmatchedLine),
      );
    });

    test('line addition resolves the corresponding unmatched line', () async {
      final review = await service.prepareReview(
        ocrResult: _ocr(['Unknown']),
        matchResult: _matches(const []),
      );

      final added = service.addItem(
        review.draft,
        product: gateway.products.first,
        sourceText: 'Unknown',
        quantity: 2,
        unitPrice: 5,
      );

      expect(added.productId, 'milk');
      expect(review.draft.items, [same(added)]);
      expect(review.draft.unmatchedLines, isEmpty);
      expect(review.draft.totals.total, 10);
    });

    test('generates unmatched, low confidence, and zero price warnings',
        () async {
      final review = await service.prepareReview(
        ocrResult: _ocr(['Mlk', 'Footer']),
        matchResult: _matches([
          _match('Mlk', 'Milk', confidence: 0.7),
        ]),
      );

      expect(
        review.draft.warnings.map((warning) => warning.type).toSet(),
        {
          ReceiptDraftWarningType.unmatchedLine,
          ReceiptDraftWarningType.lowConfidence,
          ReceiptDraftWarningType.zeroPrice,
        },
      );
    });

    test('validates required store, product, quantity, and price', () async {
      final review = await _review(service);
      review.draft.items.single
        ..productId = 'missing'
        ..quantity = 0
        ..unitPrice = -1;

      final errors = service.validate(review.draft);

      expect(errors, hasLength(4));
      expect(errors.join(' '), contains('المتجر'));
      expect(errors.join(' '), contains('منتجًا صالحًا'));
      expect(errors.join(' '), contains('كمية'));
      expect(errors.join(' '), contains('سعر'));
    });

    test('rejects invalid financial adjustments', () async {
      final review = await _review(service);
      final item = review.draft.items.single;
      service.updateUnitPrice(review.draft, item.id, 5);
      service.updateMetadata(review.draft, storeId: 'store');
      service.updateAdjustments(review.draft, discount: 6, tax: -1);

      final errors = service.validate(review.draft);

      expect(errors, hasLength(2));
      expect(errors.join(' '), contains('الخصم'));
      expect(errors.join(' '), contains('الضريبة'));
    });

    test('successful confirmation delegates the same draft to the gateway',
        () async {
      final review = await _validReview(service);

      final confirmation = await service.confirm(review.draft);

      expect(confirmation.purchaseId, 'purchase-1');
      expect(gateway.lastDraft, same(review.draft));
      expect(gateway.createCalls, 1);
    });

    test('validation failure prevents PurchaseService invocation', () async {
      final review = await _review(service);

      await expectLater(
        service.confirm(review.draft),
        throwsA(
          isA<ReceiptDraftValidationFailed>().having(
            (failure) => failure.errors,
            'errors',
            isNotEmpty,
          ),
        ),
      );
      expect(gateway.createCalls, 0);
    });

    test('cancelled import can never create a purchase', () async {
      final review = await _validReview(service);
      service.cancel(review.draft);

      await expectLater(
        service.confirm(review.draft),
        throwsA(isA<ReceiptImportCancelled>()),
      );
      expect(gateway.createCalls, 0);
    });

    test('maps repository and purchase creation failures', () async {
      gateway.error = const ReceiptPurchaseGatewayException(
        ReceiptPurchaseGatewayErrorCode.repository,
        'repository unavailable',
      );
      final review = await _validReview(service);
      await expectLater(
        service.confirm(review.draft),
        throwsA(isA<ReceiptImportRepositoryFailure>()),
      );

      gateway.error = const ReceiptPurchaseGatewayException(
        ReceiptPurchaseGatewayErrorCode.creation,
        'purchase failed',
      );
      await expectLater(
        service.confirm(review.draft),
        throwsA(isA<ReceiptPurchaseCreationFailed>()),
      );
    });

    test('maps review loading failures without leaking gateway exceptions',
        () async {
      gateway.loadError = const ReceiptPurchaseGatewayException(
        ReceiptPurchaseGatewayErrorCode.repository,
        'catalog unavailable',
      );

      await expectLater(
        service.prepareReview(
          ocrResult: _ocr(['Milk']),
          matchResult: _matches([_match('Milk', 'Milk')]),
        ),
        throwsA(
          isA<ReceiptImportRepositoryFailure>().having(
            (failure) => failure.message,
            'message',
            'catalog unavailable',
          ),
        ),
      );
    });

    test('rejects an empty OCR result', () async {
      await expectLater(
        service.prepareReview(
          ocrResult: const ReceiptOcrResult(text: '', blocks: []),
          matchResult: _matches(const []),
        ),
        throwsA(isA<InvalidReceiptDraft>()),
      );
    });

    test('manual product search supports name and category', () async {
      final review = await _review(service);

      expect(service.searchProducts(review, 'brown').single.id, 'bread');
      expect(service.searchProducts(review, 'dairy').single.id, 'milk');
      expect(service.searchProducts(review, 'unknown'), isEmpty);
    });
  });

  test('PurchaseService is the only conversion and persistence path', () async {
    final repository = _MemoryPurchaseRepository();
    final milk = PantryItem(
      id: 'milk',
      name: 'Milk',
      category: 'Dairy',
      minimum: 1,
      unit: 'unit',
      location: 'Pantry',
    );
    final purchaseService = PurchaseService(
      repository: repository,
      inventoryService: InventoryService(items: [milk]),
      clock: () => DateTime.utc(2026, 7, 21, 12),
    );
    final importService = ReceiptImportService(
      purchaseGateway: purchaseService,
      clock: () => DateTime.utc(2026, 7, 21, 10),
    );
    final review = await importService.prepareReview(
      ocrResult: _ocr(['Milk']),
      matchResult: _matches([_match('Milk', 'Milk')]),
    );
    final item = review.draft.items.single;
    importService.updateMetadata(review.draft, storeId: 'Market');
    importService.updateQuantity(review.draft, item.id, 2);
    importService.updateUnitPrice(review.draft, item.id, 3.5);

    final confirmation = await importService.confirm(review.draft);

    expect(repository.purchases, hasLength(1));
    expect(repository.items.single.quantity, 2);
    expect(repository.items.single.unitPrice, 3.5);
    expect(repository.purchases.single.total, 7);
    expect(confirmation.purchaseId, repository.purchases.single.id);
    expect(milk.quantity, 2);
    expect(milk.batches, hasLength(1));
  });
}

Future<ReceiptDraftReview> _review(ReceiptImportService service) =>
    service.prepareReview(
      ocrResult: _ocr(['Milk']),
      matchResult: _matches([_match('Milk', 'Milk')]),
    );

Future<ReceiptDraftReview> _validReview(ReceiptImportService service) async {
  final review = await _review(service);
  final item = review.draft.items.single;
  service.updateMetadata(review.draft, storeId: 'store');
  service.updateUnitPrice(review.draft, item.id, 5);
  return review;
}

ReceiptOcrResult _ocr(List<String> lines) => ReceiptOcrResult(
      text: lines.join('\n'),
      blocks: lines.isEmpty
          ? const []
          : [
              ReceiptOcrBlock(
                text: lines.join('\n'),
                lines: [
                  for (final line in lines)
                    ReceiptOcrLine(text: line, words: const []),
                ],
              ),
            ],
    );

ProductMatchResult _matches(List<MatchedProduct> matches) => ProductMatchResult(
      matches: matches,
      generatedCandidateCount: matches.length,
      evaluatedSourceCount: matches.length,
    );

MatchedProduct _match(
  String source,
  String productName, {
  double confidence = 1,
}) {
  final product = MatchableProduct(
    id: 'catalog-$productName',
    name: productName,
    category: productName == 'Milk' ? 'Dairy' : 'Bakery',
  );
  final score = MatchConfidence(confidence);
  return MatchedProduct(
    product: product,
    confidence: score,
    matchedStrategy: confidence == 1
        ? MatchingStrategyType.exact
        : MatchingStrategyType.fuzzy,
    matchedText: source,
    explanation: MatchExplanation(
      strategy: confidence == 1
          ? MatchingStrategyType.exact
          : MatchingStrategyType.fuzzy,
      normalizedOcrText: source.toLowerCase(),
      normalizedProductText: productName.toLowerCase(),
      similarityScore: confidence,
      finalConfidence: score,
    ),
  );
}

class _MockReceiptPurchaseGateway implements ReceiptPurchaseGateway {
  final List<ReceiptDraftProductOption> products = const [
    ReceiptDraftProductOption(
      id: 'milk',
      name: 'Milk',
      category: 'Dairy',
      unit: 'unit',
    ),
    ReceiptDraftProductOption(
      id: 'bread',
      name: 'Brown Bread',
      category: 'Bakery',
      unit: 'unit',
    ),
  ];
  final List<ReceiptDraftStoreOption> stores = const [
    ReceiptDraftStoreOption(id: 'store', name: 'Market'),
  ];
  Object? loadError;
  Object? error;
  ReceiptDraft? lastDraft;
  int createCalls = 0;

  @override
  List<ReceiptDraftProductOption> receiptImportProducts() {
    if (loadError case final current?) throw current;
    return products;
  }

  @override
  Future<List<ReceiptDraftStoreOption>> receiptImportStores() async {
    if (loadError case final current?) throw current;
    return stores;
  }

  @override
  Future<ReceiptImportConfirmation> createPurchaseFromReceiptDraft(
    ReceiptDraft draft,
  ) async {
    createCalls++;
    lastDraft = draft;
    if (error case final current?) throw current;
    return ReceiptImportConfirmation(
      purchaseId: 'purchase-1',
      total: draft.totals.total,
      purchaseDate: draft.metadata.purchaseDate,
    );
  }
}

class _MemoryPurchaseRepository implements PurchaseRepository {
  final List<Purchase> purchases = [];
  final List<PurchaseItem> items = [];

  @override
  Future<Purchase> createPurchase(
    Purchase purchase,
    List<PurchaseItem> purchaseItems,
  ) async {
    purchases.add(purchase);
    items.addAll(purchaseItems);
    return purchase;
  }

  @override
  Future<void> deletePurchase(String purchaseId) async {
    purchases.removeWhere((purchase) => purchase.id == purchaseId);
    items.removeWhere((item) => item.purchaseId == purchaseId);
  }

  @override
  Future<Purchase?> readPurchase(String purchaseId) async {
    for (final purchase in purchases) {
      if (purchase.id == purchaseId) return purchase;
    }
    return null;
  }

  @override
  Future<List<PurchaseItem>> readPurchaseDetails(String purchaseId) async =>
      items.where((item) => item.purchaseId == purchaseId).toList();

  @override
  Future<List<Purchase>> readPurchaseHistory() async => List.of(purchases);

  @override
  Future<List<Purchase>> readPurchasesByDate(DateTime date) async => purchases
      .where(
        (purchase) =>
            purchase.purchaseDate.year == date.year &&
            purchase.purchaseDate.month == date.month &&
            purchase.purchaseDate.day == date.day,
      )
      .toList();

  @override
  Future<List<Purchase>> readPurchasesByStore(String storeId) async =>
      purchases.where((purchase) => purchase.storeId == storeId).toList();

  @override
  Future<Purchase> updatePurchase(
    Purchase purchase,
    List<PurchaseItem> purchaseItems,
  ) async {
    final index = purchases.indexWhere((current) => current.id == purchase.id);
    purchases[index] = purchase;
    items.removeWhere((item) => item.purchaseId == purchase.id);
    items.addAll(purchaseItems);
    return purchase;
  }
}
