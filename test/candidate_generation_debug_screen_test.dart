import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching_v2/application/candidate_generation_debug_service.dart';
import 'package:maqadi_v2/product_matching_v2/application/candidate_generation_service.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_catalog_entry.dart';
import 'package:maqadi_v2/product_matching_v2/infrastructure/mapped_receipt_line_text_resolver.dart';
import 'package:maqadi_v2/product_matching_v2/presentation/candidate_generation_debug_screen.dart';
import 'package:maqadi_v2/receipt_line_builder/application/receipt_line_builder_service.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_line_builder/presentation/receipt_line_builder_debug_screen.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  testWidgets(
      'navigates from Receipt Line debug and renders candidates with evidence',
      (tester) async {
    final elements = [
      receiptElement(
        'product',
        ReceiptElementType.productName,
        text: ' FRESH,   MILK! ',
        width: 40,
      ),
      receiptElement('price', ReceiptElementType.price, x: 45),
    ];
    final resolver = MappedReceiptLineTextResolver({
      for (final element in elements) element.id: element.text,
    });
    final debugService = CandidateGenerationDebugService(
      catalog: _Catalog([
        ProductCatalogEntry(id: 'exact', displayName: 'Fresh Milk'),
        ProductCatalogEntry(id: 'token', displayName: 'Milk Powder'),
      ]),
      textResolver: resolver,
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ReceiptLineBuilderDebugScreen(
          service: const ReceiptLineBuilderService(),
          elements: elements,
          onInspectCandidates: (result) {
            Navigator.of(context).push<void>(MaterialPageRoute<void>(
              builder: (_) => CandidateGenerationDebugScreen(
                service: debugService,
                lines: result.lines,
              ),
            ));
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('open-candidate-generation-debug')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('open-candidate-generation-debug')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('candidate-generation-debug-screen')),
        findsOneWidget);
    expect(find.textContaining('Receipt Line:'), findsOneWidget);
    expect(
        find.text('Original product text:  FRESH,   MILK! '), findsOneWidget);
    expect(
      find.text('Pre-correction normalized text: fresh milk'),
      findsOneWidget,
    );
    expect(find.text('Final normalized query: fresh milk'), findsOneWidget);
    expect(find.text('Candidate count: 2'), findsOneWidget);
    expect(find.text('Catalog entry count: 2'), findsOneWidget);
    expect(find.text('Valid catalog entry count: 2'), findsOneWidget);
    expect(find.text('Invalid catalog entry count: 0'), findsOneWidget);
    expect(find.text('Entries evaluated: 2'), findsOneWidget);
    expect(find.text('Accepted: 2'), findsOneWidget);
    expect(find.text('Ranking: Executed'), findsOneWidget);
    expect(find.text('Selection: Not executed'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated-candidate-exact')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('generated-candidate-token')),
        findsOneWidget);
    expect(find.text('Candidate type: exactMatch'), findsOneWidget);
    expect(find.text('Evaluation / generation order: 1 / 1'), findsOneWidget);
    expect(find.text('Rank: 1'), findsOneWidget);
    expect(find.text('Rank: 2'), findsOneWidget);
    expect(find.text('Score: 0.95'), findsOneWidget);
    expect(find.text('Score: 0.3'), findsOneWidget);
    expect(find.text('Confidence: 0.0'), findsNWidgets(2));
    expect(find.textContaining('Ranking Evidence:'), findsNWidgets(2));
    expect(find.text('Normalized text matched: fresh milk'), findsOneWidget);
    expect(find.text('Exact normalized match: true'), findsOneWidget);
    expect(find.text('Matched tokens: fresh, milk'), findsOneWidget);
    expect(find.text('Catalog lookup: catalogName'), findsNWidgets(2));
    expect(find.text('Matched Through: Canonical Name'), findsNWidgets(2));
    expect(find.text('Matched Alias: None'), findsNWidgets(2));
  });

  testWidgets('renders the exact alias used for discovery', (tester) async {
    final elements = productRow();
    final lines = const ReceiptLineBuilderEngine().build(elements).lines;
    await tester.pumpWidget(_debugApp(
      lines: lines,
      resolver: _Resolver('Garlic Bag'),
      catalog: _Catalog([
        ProductCatalogEntry(
          id: 'garlic',
          displayName: 'ثوم',
          aliases: const ['garlic bag'],
        ),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Matched Through: Alias'), findsOneWidget);
    expect(find.text('Matched Alias: garlic bag'), findsOneWidget);
    expect(find.text('Ranking: Executed'), findsOneWidget);
    expect(find.text('Selection: Not executed'), findsOneWidget);
  });

  testWidgets('shows no-product-text and no-candidate-match line reasons',
      (tester) async {
    final elements = [
      receiptElement(
        'product',
        ReceiptElementType.productName,
        text: 'Milk',
        width: 40,
      ),
      receiptElement('price', ReceiptElementType.price, x: 45),
      receiptElement('orphan', ReceiptElementType.price, y: 30),
    ];
    final lines = const ReceiptLineBuilderEngine().build(elements).lines;
    await tester.pumpWidget(_debugApp(
      lines: lines,
      resolver: MappedReceiptLineTextResolver({
        for (final element in elements) element.id: element.text,
      }),
      catalog: _Catalog([
        ProductCatalogEntry(id: 'bread', displayName: 'Bread'),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('candidate-generation-debug-results')),
        findsOneWidget);
    expect(find.text('No candidate match'), findsOneWidget);
    expect(find.text('No product text'), findsWidgets);
    expect(find.text('Candidate count: 0'), findsNWidgets(2));
  });

  testWidgets('shows an empty-catalog reason and no ranking or selection',
      (tester) async {
    final elements = productRow();
    final lines = const ReceiptLineBuilderEngine().build(elements).lines;
    await tester.pumpWidget(_debugApp(
      lines: lines,
      resolver: MappedReceiptLineTextResolver({
        for (final element in elements) element.id: element.text,
      }),
      catalog: _Catalog(const []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Empty catalog'), findsOneWidget);
    expect(find.text('Ranking: Executed'), findsOneWidget);
    expect(find.text('Selection: Not executed'), findsOneWidget);
  });

  testWidgets('identifies duplicate normalized queries without merging lines',
      (tester) async {
    final elements = [
      receiptElement(
        'product-1',
        ReceiptElementType.productName,
        text: 'GÄRLIC -BAG',
        width: 40,
      ),
      receiptElement('price-1', ReceiptElementType.price, x: 45),
      receiptElement(
        'product-2',
        ReceiptElementType.productName,
        text: 'GARLIC -BAG',
        y: 30,
        width: 40,
      ),
      receiptElement('price-2', ReceiptElementType.price, x: 45, y: 30),
    ];
    final lines = const ReceiptLineBuilderEngine().build(elements).lines;
    final service = CandidateGenerationDebugService(
      catalog: _Catalog(const []),
      textResolver: MappedReceiptLineTextResolver({
        for (final element in elements) element.id: element.text,
      }),
    );
    final inspected = await service.inspect(lines);
    await tester.pumpWidget(MaterialApp(
      home: CandidateGenerationDebugScreen(
        service: service,
        lines: lines,
      ),
    ));
    await tester.pumpAndSettle();

    expect(lines, hasLength(2));
    expect(inspected, hasLength(2));
    expect(
      inspected.every(
        (value) =>
            value.hasDuplicateNormalizedQuery &&
            value.duplicateNormalizedQueryLineIds.length == 2,
      ),
      isTrue,
    );
    expect(
      find.text('Duplicate normalized query: garlic bag'),
      findsOneWidget,
    );
    expect(find.textContaining('Related Receipt Line IDs:'), findsOneWidget);
    expect(find.text('Candidate count: 0'), findsOneWidget);
  });
}

Widget _debugApp({
  required List<ReceiptLine> lines,
  required ReceiptLineProductTextResolver resolver,
  required ProductCandidateCatalog catalog,
}) =>
    MaterialApp(
      home: CandidateGenerationDebugScreen(
        service: CandidateGenerationDebugService(
          catalog: catalog,
          textResolver: resolver,
        ),
        lines: lines,
      ),
    );

class _Catalog implements ProductCandidateCatalog {
  const _Catalog(this.products);

  final List<ProductCatalogEntry> products;

  @override
  Future<List<ProductCatalogEntry>> readProducts() async => products;
}

class _Resolver implements ReceiptLineProductTextResolver {
  const _Resolver(this.value);

  final String value;

  @override
  Future<String?> resolve(ReceiptLine line) async => value;
}
