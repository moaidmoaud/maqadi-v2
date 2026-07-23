import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching_v2/domain/candidate_generation_diagnostics.dart';
import 'package:maqadi_v2/product_matching_v2/application/candidate_generation_service.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_catalog_entry.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_evidence.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_reason.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_trace.dart';
import 'package:maqadi_v2/product_matching_v2/engine/candidate_text_normalizer.dart';
import 'package:maqadi_v2/product_matching_v2/infrastructure/catalog_product_candidate_catalog.dart';
import 'package:maqadi_v2/products.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  final line =
      const ReceiptLineBuilderEngine().build(productRow()).lines.single;

  test('normalizes case, punctuation, and repeated whitespace', () {
    const normalizer = CandidateTextNormalizer();

    expect(normalizer.normalize('  FRESH,   Milk!! '), 'fresh milk');
    expect(normalizer.normalize('  حليب،   طازج!!! '), 'حليب طازج');
  });

  test('folds accented Latin letters to their base characters', () {
    const normalizer = CandidateTextNormalizer();

    expect(normalizer.normalize('GÄRLIC -BAG'), 'garlic bag');
    expect(normalizer.normalize('PÖTATOES -BAG'), 'potatoes bag');
    expect(normalizer.normalize('CAFÉ'), 'cafe');
    expect(normalizer.normalize('CAFE\u0301 AU LAIT'), 'cafe au lait');
  });

  test('preserves Arabic text without transliteration', () {
    const normalizer = CandidateTextNormalizer();

    final result = normalizer.normalizeWithTrace('كريمة طَبخ');

    expect(result.normalizedText, 'كريمة طَبخ');
  });

  test('corrects a zero between letters and records the operation', () {
    const normalizer = CandidateTextNormalizer();

    final result = normalizer.normalizeWithTrace('PUCK C0OKING CREAM');

    expect(result.preCorrectionNormalizedText, 'puck c0oking cream');
    expect(result.normalizedText, 'puck cooking cream');
    expect(
      result.appliedOperations,
      contains(CandidateNormalizationOperation.correctedOcrZeroBetweenLetters),
    );
  });

  test('does not corrupt numeric product values', () {
    const normalizer = CandidateTextNormalizer();

    expect(normalizer.normalize('Water 500 ml'), 'water 500 ml');
    expect(normalizer.normalize('Vitamin B12'), 'vitamin b12');
    expect(normalizer.normalize('A0B'), 'a0b');
  });

  test('generates a candidate for an accented query matching catalog text',
      () async {
    final service = CandidateGenerationService(
      catalog: _Catalog([
        ProductCatalogEntry(id: 'garlic', displayName: 'Garlic Bag'),
      ]),
      textResolver: _Resolver('GÄRLIC -BAG'),
    );

    final candidates = await service.generate(line);

    expect(candidates.map((value) => value.productId), ['garlic']);
    expect(candidates.single.matchReason, ProductMatchReason.exactMatch);
  });

  test('generates every valid catalog candidate without scoring or ranking',
      () async {
    ProductMatchTrace? trace;
    final service = CandidateGenerationService(
      catalog: _Catalog([
        ProductCatalogEntry(id: 'exact', displayName: 'Fresh Milk'),
        ProductCatalogEntry(id: 'token', displayName: 'Milk Powder'),
        ProductCatalogEntry(id: 'other', displayName: 'Bread'),
        ProductCatalogEntry(
          id: 'alias',
          displayName: 'Long Life Beverage',
          aliases: const ['Fresh Milk'],
        ),
        ProductCatalogEntry(id: '', displayName: 'Fresh Milk'),
        ProductCatalogEntry(
          id: 'invalid-name',
          displayName: '',
          aliases: const ['Fresh Milk'],
        ),
      ]),
      textResolver: _Resolver(' FRESH,  MILK! '),
      onTrace: (value) => trace = value,
    );

    final candidates = await service.generate(line);

    expect(candidates.map((value) => value.productId),
        ['exact', 'token', 'alias']);
    expect(candidates.every((value) => value.matchingScore == 0), isTrue);
    expect(candidates.every((value) => value.confidence == 0), isTrue);
    expect(trace!.candidateRanking, isEmpty);
    expect(trace!.winningCandidate, isNull);
    expect(trace!.rejectedCandidates, isEmpty);
  });

  test('returns an empty candidate list for an empty catalog', () async {
    ProductMatchTrace? trace;
    final service = CandidateGenerationService(
      catalog: _Catalog(const []),
      textResolver: _Resolver('Milk'),
      onTrace: (value) => trace = value,
    );

    final candidates = await service.generate(line);

    expect(candidates, isEmpty);
    expect(trace!.normalizedQuery, 'milk');
    expect(trace!.generatedCandidateCount, 0);
    expect(trace!.generatedCandidateIds, isEmpty);
    expect(
      trace!.candidateGenerationDiagnostics!.reason,
      CandidateGenerationDiagnosticReason.emptyCatalog,
    );
  });

  test('diagnoses non-empty catalog with no candidate match', () async {
    ProductMatchTrace? trace;
    final service = CandidateGenerationService(
      catalog: _Catalog([
        ProductCatalogEntry(id: 'bread', displayName: 'Bread'),
        ProductCatalogEntry(id: 'milk', displayName: 'Milk'),
      ]),
      textResolver: _Resolver('Garlic Bag'),
      onTrace: (value) => trace = value,
    );

    expect(await service.generate(line), isEmpty);
    final diagnostics = trace!.candidateGenerationDiagnostics!;
    expect(
      diagnostics.reason,
      CandidateGenerationDiagnosticReason.noCandidateMatch,
    );
    expect(diagnostics.catalogEntryCount, 2);
    expect(diagnostics.validCatalogEntryCount, 2);
    expect(diagnostics.invalidCatalogEntryCount, 0);
    expect(diagnostics.evaluatedEntryCount, 2);
    expect(diagnostics.rejectedNoTextCount, 0);
    expect(diagnostics.rejectedNoTokenOverlapCount, 2);
    expect(diagnostics.acceptedCount, 0);
  });

  test('distinguishes a catalog with no valid entries', () async {
    ProductMatchTrace? trace;
    final service = CandidateGenerationService(
      catalog: _Catalog([
        ProductCatalogEntry(id: '', displayName: 'Milk'),
        ProductCatalogEntry(id: 'missing-name', displayName: ''),
      ]),
      textResolver: _Resolver('Milk'),
      onTrace: (value) => trace = value,
    );

    expect(await service.generate(line), isEmpty);
    final diagnostics = trace!.candidateGenerationDiagnostics!;
    expect(
      diagnostics.reason,
      CandidateGenerationDiagnosticReason.noValidCatalogEntries,
    );
    expect(diagnostics.catalogEntryCount, 2);
    expect(diagnostics.validCatalogEntryCount, 0);
    expect(diagnostics.invalidCatalogEntryCount, 2);
  });

  test('reports catalog validity duplicate and preview counts', () async {
    ProductMatchTrace? trace;
    final service = CandidateGenerationService(
      catalog: _Catalog([
        ProductCatalogEntry(id: 'milk', displayName: 'Milk'),
        ProductCatalogEntry(id: 'milk', displayName: 'Fresh Milk'),
        ProductCatalogEntry(id: '', displayName: 'Milk'),
        ProductCatalogEntry(id: 'punctuation', displayName: '---'),
      ]),
      textResolver: _Resolver('Milk'),
      onTrace: (value) => trace = value,
    );

    await service.generate(line);
    final diagnostics = trace!.candidateGenerationDiagnostics!;

    expect(diagnostics.catalogEntryCount, 4);
    expect(diagnostics.validCatalogEntryCount, 3);
    expect(diagnostics.invalidCatalogEntryCount, 1);
    expect(diagnostics.duplicateProductIdCount, 1);
    expect(diagnostics.evaluatedEntryCount, 2);
    expect(diagnostics.rejectedNoTextCount, 1);
    expect(diagnostics.acceptedCount, 1);
    expect(
      diagnostics.catalogPreview.map((value) => value.normalizedName),
      ['milk', 'fresh milk'],
    );
  });

  test('runtime catalog adapter exposes deterministic catalog diagnostics',
      () async {
    ProductMatchTrace? trace;
    final service = CandidateGenerationService(
      catalog: const CatalogProductCandidateCatalog(),
      textResolver: _Resolver('Unlisted English Product'),
      onTrace: (value) => trace = value,
    );

    expect(await service.generate(line), isEmpty);
    final diagnostics = trace!.candidateGenerationDiagnostics!;

    expect(diagnostics.catalogEntryCount, products.length);
    expect(diagnostics.validCatalogEntryCount, products.length);
    expect(diagnostics.invalidCatalogEntryCount, 0);
    expect(diagnostics.duplicateProductIdCount, 0);
    expect(diagnostics.evaluatedEntryCount, products.length);
    expect(diagnostics.rejectedNoTokenOverlapCount, products.length);
    expect(
      diagnostics.reason,
      CandidateGenerationDiagnosticReason.noCandidateMatch,
    );
    expect(diagnostics.catalogPreview, hasLength(5));
    expect(diagnostics.catalogPreview.first.normalizedName, 'طماطم');
  });

  test('prevents duplicate product IDs while preserving generation order',
      () async {
    final service = CandidateGenerationService(
      catalog: _Catalog([
        ProductCatalogEntry(id: 'milk', displayName: 'Milk'),
        ProductCatalogEntry(id: 'milk', displayName: 'Fresh Milk'),
        ProductCatalogEntry(id: 'powder', displayName: 'Milk Powder'),
      ]),
      textResolver: _Resolver('Milk'),
    );

    final candidates = await service.generate(line);

    expect(candidates.map((value) => value.productId), ['milk', 'powder']);
    expect(() => candidates.clear(), throwsUnsupportedError);
  });

  test('emits normalization, discovery evidence, and generation trace',
      () async {
    ProductMatchTrace? trace;
    final catalog = _Catalog([
      ProductCatalogEntry(id: 'exact', displayName: 'Fresh Milk'),
      ProductCatalogEntry(id: 'other', displayName: 'Bread'),
      ProductCatalogEntry(id: 'token', displayName: 'Milk Powder'),
    ]);
    final resolver = _Resolver(' FRESH... Milk ');
    final service = CandidateGenerationService(
      catalog: catalog,
      textResolver: resolver,
      onTrace: (value) => trace = value,
    );

    await service.generate(line);
    final value = trace!;

    expect(resolver.calls, 1);
    expect(catalog.calls, 1);
    expect(value.normalizedQuery, 'fresh milk');
    expect(value.originalQueryText, ' FRESH... Milk ');
    expect(value.preCorrectionNormalizedQuery, 'fresh milk');
    expect(value.evaluationOrder, ['exact', 'other', 'token']);
    expect(value.generatedCandidateCount, 2);
    expect(value.generatedCandidateIds, ['exact', 'token']);
    expect(value.generationOrder, ['exact', 'token']);
    expect(value.finalDecision, ProductMatchReason.notEvaluated);
    expect(value.evidence['ranking'], 'notPerformed');
    expect(value.evidence['selection'], 'notPerformed');
    expect(value.discoveryEvidence['exact']!.exactNormalizedMatch, isTrue);
    expect(
      value.discoveryEvidence['exact']!.discoverySource,
      ProductMatchDiscoverySource.catalogName,
    );
    expect(value.discoveryEvidence['token']!.matchedTokens, ['milk']);
    expect(
      value.candidateGenerationDiagnostics!.reason,
      CandidateGenerationDiagnosticReason.candidatesGenerated,
    );
  });
}

class _Catalog implements ProductCandidateCatalog {
  _Catalog(this.products);

  final List<ProductCatalogEntry> products;
  int calls = 0;

  @override
  Future<List<ProductCatalogEntry>> readProducts() async {
    calls++;
    return products;
  }
}

class _Resolver implements ReceiptLineProductTextResolver {
  _Resolver(this.text);

  final String? text;
  int calls = 0;

  @override
  Future<String?> resolve(ReceiptLine line) async {
    calls++;
    return text;
  }
}
