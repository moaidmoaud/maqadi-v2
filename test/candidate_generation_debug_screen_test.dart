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
    expect(find.text('Normalized query: fresh milk'), findsOneWidget);
    expect(find.text('Candidate count: 2'), findsOneWidget);
    expect(find.text('Ranking: Not executed'), findsOneWidget);
    expect(find.text('Selection: Not executed'), findsOneWidget);
    expect(find.byKey(const ValueKey('generated-candidate-exact')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('generated-candidate-token')),
        findsOneWidget);
    expect(find.text('Candidate type: exactMatch'), findsOneWidget);
    expect(find.text('Evaluation / generation order: 1 / 1'), findsOneWidget);
    expect(find.text('Score: 0.0'), findsNWidgets(2));
    expect(find.text('Confidence: 0.0'), findsNWidgets(2));
    expect(find.text('Normalized text matched: fresh milk'), findsOneWidget);
    expect(find.text('Exact normalized match: true'), findsOneWidget);
    expect(find.text('Matched tokens: fresh, milk'), findsOneWidget);
    expect(find.text('Catalog lookup: catalogName'), findsNWidgets(2));
  });

  testWidgets('shows no-product-text and no-valid-candidates line reasons',
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
    expect(find.text('No valid candidates'), findsOneWidget);
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
    expect(find.text('Ranking: Not executed'), findsOneWidget);
    expect(find.text('Selection: Not executed'), findsOneWidget);
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
