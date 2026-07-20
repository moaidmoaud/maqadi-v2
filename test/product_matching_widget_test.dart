import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching/application/product_matching_service.dart';
import 'package:maqadi_v2/product_matching/domain/product_match_models.dart';
import 'package:maqadi_v2/product_matching/domain/product_matching_repository.dart';
import 'package:maqadi_v2/product_matching/engine/matching_engine.dart';
import 'package:maqadi_v2/product_matching/presentation/product_matching_screen.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';

void main() {
  testWidgets('shows loading while the product catalog is loading',
      (tester) async {
    final repository = _WidgetRepository(_products)
      ..pending = Completer<List<MatchableProduct>>();

    await _pumpScreen(tester, repository, ['Fresh Milk']);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('جارٍ مطابقة المنتجات...'), findsOneWidget);
  });

  testWidgets('shows ranked candidates and allows candidate selection',
      (tester) async {
    MatchedProduct? selected;
    await _pumpScreen(
      tester,
      _WidgetRepository(_products),
      ['Fresh Milk'],
      onSelected: (match) => selected = match,
    );
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('product-match-candidates')), findsOneWidget);
    expect(find.byKey(const ValueKey('select-product-milk')), findsOneWidget);
    expect(find.text('100٪'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('select-product-milk')));
    await tester.pump();

    expect(selected!.product.id, 'milk');
    expect(find.text('تم الاختيار'), findsOneWidget);
  });

  testWidgets('supports manual search after no OCR match', (tester) async {
    await _pumpScreen(
      tester,
      _WidgetRepository(_products),
      ['receipt total'],
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('product-match-empty')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('product-match-search')),
      'Brown Bread',
    );
    await tester.tap(
      find.byKey(const ValueKey('product-match-search-button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('select-product-bread')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('product-match-candidates')), findsOneWidget);
  });

  testWidgets('shows an error and retries through the service', (tester) async {
    final repository = _WidgetRepository(_products)
      ..errors.add(const ProductMatchingRepositoryException('offline'));
    await _pumpScreen(tester, repository, ['Fresh Milk']);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('product-match-error')), findsOneWidget);
    expect(find.text('offline'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('product-match-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('select-product-milk')), findsOneWidget);
    expect(repository.readCalls, 2);
  });

  testWidgets('skips an OCR line and reruns matching without that line',
      (tester) async {
    await _pumpScreen(
      tester,
      _WidgetRepository(_products),
      ['Fresh Milk', 'Brown Bread'],
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('select-product-milk')), findsOneWidget);
    expect(find.byKey(const ValueKey('select-product-bread')), findsOneWidget);

    await tester.tap(find.byTooltip('تخطي السطر').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('select-product-milk')), findsNothing);
    expect(find.byKey(const ValueKey('select-product-bread')), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ProductMatchingRepository repository,
  List<String> lines, {
  ValueChanged<MatchedProduct>? onSelected,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ProductMatchingScreen(
          service: ProductMatchingService(
            engine: MatchingEngine(repository: repository),
          ),
          request: ProductMatchRequest(ocrResult: _ocrResult(lines)),
          onSelected: onSelected,
        ),
      ),
    ),
  );
}

ReceiptOcrResult _ocrResult(List<String> lines) => ReceiptOcrResult(
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

const _products = [
  MatchableProduct(
    id: 'milk',
    name: 'Fresh Milk',
    category: 'Dairy',
    aliases: ['حليب'],
  ),
  MatchableProduct(
    id: 'bread',
    name: 'Brown Bread',
    category: 'Bakery',
    aliases: ['خبز'],
  ),
];

class _WidgetRepository implements ProductMatchingRepository {
  _WidgetRepository(this.products);

  final List<MatchableProduct> products;
  final List<Object> errors = [];
  Completer<List<MatchableProduct>>? pending;
  int readCalls = 0;

  @override
  Future<List<MatchableProduct>> readProducts() async {
    readCalls++;
    if (errors.isNotEmpty) throw errors.removeAt(0);
    if (pending case final completer?) return completer.future;
    return products;
  }
}
