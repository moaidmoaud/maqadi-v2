import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/product_matching/domain/product_match_models.dart';
import 'package:maqadi_v2/purchase/application/purchase_creation_gateway.dart';
import 'package:maqadi_v2/purchase/domain/purchase_creation_command.dart';
import 'package:maqadi_v2/receipt_import/application/receipt_import_service.dart';
import 'package:maqadi_v2/receipt_import/domain/receipt_draft.dart';
import 'package:maqadi_v2/receipt_import/presentation/receipt_review_screen.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';

void main() {
  testWidgets('shows loading while receipt review data is prepared', (
    tester,
  ) async {
    final gateway = _WidgetReceiptGateway()
      ..pendingStores = Completer<List<Store>>();

    await _pumpReview(tester, gateway);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('جارٍ تجهيز مسودة الإيصال...'), findsOneWidget);
  });

  testWidgets('shows draft items, warnings, totals, and unmatched lines', (
    tester,
  ) async {
    await _pumpReview(tester, _WidgetReceiptGateway(), includeUnmatched: true);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('receipt-review-content')),
      findsOneWidget,
    );
    expect(find.text('Milk'), findsWidgets);
    expect(
      find.byKey(const ValueKey('receipt-draft-warnings')),
      findsOneWidget,
    );
    expect(find.text('Receipt total'), findsWidgets);
    expect(find.byKey(const ValueKey('receipt-draft-totals')), findsOneWidget);
  });

  testWidgets('shows friendly validation without creating a purchase', (
    tester,
  ) async {
    final gateway = _WidgetReceiptGateway();
    await _pumpReview(tester, gateway);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('confirm-receipt-import')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('receipt-import-validation')),
      findsOneWidget,
    );
    expect(find.textContaining('اختر المتجر'), findsOneWidget);
    expect(gateway.createCalls, 0);
  });

  testWidgets('edits quantity and price then confirms through the gateway', (
    tester,
  ) async {
    final gateway = _WidgetReceiptGateway();
    ReceiptImportConfirmation? confirmed;
    await _pumpReview(
      tester,
      gateway,
      onConfirmed: (value) => confirmed = value,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('receipt-import-store')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();

    final quantity = _keyStartsWith('receipt-quantity-');
    final price = _keyStartsWith('receipt-price-');
    await tester.ensureVisible(quantity);
    await tester.enterText(quantity, '2');
    await tester.enterText(price, '4.5');
    await tester.pump();

    final confirm = find.byKey(const ValueKey('confirm-receipt-import'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(gateway.createCalls, 1);
    expect(gateway.lastCommand!.items.single.quantity, 2);
    expect(gateway.lastCommand!.items.single.unitPrice, 4.5);
    expect(confirmed!.purchaseId, 'purchase-widget');
  });

  testWidgets('double tap starts only one purchase creation', (tester) async {
    final gateway = _WidgetReceiptGateway()
      ..pendingCreation = Completer<PurchaseCreationResult>();
    await _pumpReview(tester, gateway, onConfirmed: (_) {});
    await tester.pumpAndSettle();
    await _completeRequiredFields(tester);

    final confirm = find.byKey(const ValueKey('confirm-receipt-import'));
    await tester.tap(confirm);
    await tester.tap(confirm);
    await tester.pump();

    expect(gateway.createCalls, 1);
    gateway.pendingCreation!.complete(
      PurchaseCreationResult(
        purchaseId: 'purchase-widget',
        total: 5,
        purchaseDate: DateTime.utc(2026, 7, 21),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
  });

  testWidgets('successful import removes the complete receipt route stack', (
    tester,
  ) async {
    final gateway = _WidgetReceiptGateway();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('home-screen')),
      ),
    );
    for (final name in ['capture', 'ocr', 'matching']) {
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: name),
          builder: (_) => Scaffold(body: Text(name)),
        ),
      );
      await tester.pumpAndSettle();
    }
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'review'),
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: ReceiptReviewScreen(
            service: ReceiptImportService(
              purchaseGateway: gateway,
              clock: () => DateTime.utc(2026, 7, 21, 10),
            ),
            ocrResult: _ocr(['Milk']),
            matchResult: _matches(),
            terminateReceiptFlowOnConfirm: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _completeRequiredFields(tester);

    await tester.tap(find.byKey(const ValueKey('confirm-receipt-import')));
    await tester.pumpAndSettle();

    expect(find.text('home-screen'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-review-screen')), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(gateway.createCalls, 1);
  });

  testWidgets('searches manually and replaces the selected product', (
    tester,
  ) async {
    await _pumpReview(tester, _WidgetReceiptGateway());
    await tester.pumpAndSettle();

    final replace = _keyStartsWith('replace-receipt-product-');
    await tester.ensureVisible(replace);
    await tester.tap(replace);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('receipt-product-search')),
      'bread',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('select-receipt-product-bread')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Brown Bread'), findsOneWidget);
  });

  testWidgets('removes a line and adds it back from unmatched lines', (
    tester,
  ) async {
    await _pumpReview(tester, _WidgetReceiptGateway());
    await tester.pumpAndSettle();

    await tester.tap(_keyStartsWith('remove-receipt-item-'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('receipt-draft-empty')), findsOneWidget);
    final addUnmatched = find.byKey(
      ValueKey('add-unmatched-${'Milk'.hashCode}'),
    );
    await tester.ensureVisible(addUnmatched);
    await tester.tap(addUnmatched);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-receipt-product-milk')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('receipt-draft-empty')), findsNothing);
    expect(_keyStartsWith('receipt-quantity-'), findsOneWidget);
  });

  testWidgets('shows an error state and retries preparation', (tester) async {
    final gateway = _WidgetReceiptGateway()
      ..loadErrors.add(
        const PurchaseCreationException(
          PurchaseCreationErrorCode.repository,
          'catalog offline',
        ),
      );
    await _pumpReview(tester, gateway);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('receipt-review-error')), findsOneWidget);
    expect(find.text('catalog offline'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('receipt-review-retry')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('receipt-review-content')),
      findsOneWidget,
    );
  });

  testWidgets('cancel action does not create a purchase', (tester) async {
    final gateway = _WidgetReceiptGateway();
    await _pumpReview(tester, gateway);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('receipt-import-cancel')));
    await tester.pumpAndSettle();

    expect(gateway.createCalls, 0);
  });
}

Finder _keyStartsWith(String prefix) => find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> && key.value.startsWith(prefix);
    });

Future<void> _completeRequiredFields(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('receipt-import-store')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Market').last);
  await tester.pumpAndSettle();
  final price = _keyStartsWith('receipt-price-');
  await tester.ensureVisible(price);
  await tester.enterText(price, '5');
  await tester.pump();
}

Future<void> _pumpReview(
  WidgetTester tester,
  _WidgetReceiptGateway gateway, {
  bool includeUnmatched = false,
  ValueChanged<ReceiptImportConfirmation>? onConfirmed,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final lines = ['Milk', if (includeUnmatched) 'Receipt total'];
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ReceiptReviewScreen(
          service: ReceiptImportService(
            purchaseGateway: gateway,
            clock: () => DateTime.utc(2026, 7, 21, 10),
          ),
          ocrResult: _ocr(lines),
          matchResult: _matches(),
          onConfirmed: onConfirmed,
        ),
      ),
    ),
  );
}

ReceiptOcrResult _ocr(List<String> lines) => ReceiptOcrResult(
      text: lines.join('\n'),
      blocks: [
        ReceiptOcrBlock(
          text: lines.join('\n'),
          lines: [
            for (final line in lines)
              ReceiptOcrLine(text: line, words: const []),
          ],
        ),
      ],
    );

ProductMatchResult _matches() {
  const product = MatchableProduct(
    id: 'catalog-milk',
    name: 'Milk',
    category: 'Dairy',
  );
  const confidence = MatchConfidence(1);
  return const ProductMatchResult(
    matches: [
      MatchedProduct(
        product: product,
        confidence: confidence,
        matchedStrategy: MatchingStrategyType.exact,
        matchedText: 'Milk',
        explanation: MatchExplanation(
          strategy: MatchingStrategyType.exact,
          normalizedOcrText: 'milk',
          normalizedProductText: 'milk',
          similarityScore: 1,
          finalConfidence: confidence,
        ),
      ),
    ],
    generatedCandidateCount: 1,
    evaluatedSourceCount: 1,
  );
}

class _WidgetReceiptGateway implements PurchaseCreationGateway {
  final List<PurchaseProductOption> products = const [
    PurchaseProductOption(
      id: 'milk',
      name: 'Milk',
      category: 'Dairy',
      unit: 'unit',
    ),
    PurchaseProductOption(
      id: 'bread',
      name: 'Brown Bread',
      category: 'Bakery',
      unit: 'unit',
    ),
  ];
  final List<Store> stores = [
    Store(id: 'store', name: 'Market', createdAt: DateTime.utc(2026, 1, 1)),
  ];
  final List<Object> loadErrors = [];
  Completer<List<Store>>? pendingStores;
  PurchaseCreationCommand? lastCommand;
  Completer<PurchaseCreationResult>? pendingCreation;
  int createCalls = 0;

  @override
  List<PurchaseProductOption> purchaseCreationProducts() {
    if (loadErrors.isNotEmpty) throw loadErrors.removeAt(0);
    return products;
  }

  @override
  Future<List<Store>> purchaseCreationStores() async {
    if (pendingStores case final pending?) return pending.future;
    return stores;
  }

  @override
  Future<PurchaseCreationResult> createFromCommand(
    PurchaseCreationCommand command,
  ) async {
    createCalls++;
    lastCommand = command;
    if (pendingCreation case final pending?) return pending.future;
    return PurchaseCreationResult(
      purchaseId: 'purchase-widget',
      total: command.items.fold(
        0,
        (total, item) => total + item.quantity * item.unitPrice,
      ),
      purchaseDate: command.purchaseDate,
    );
  }
}
