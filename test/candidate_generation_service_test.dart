import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching_v2/application/candidate_generation_service.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_catalog_entry.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_evidence.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_reason.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_trace.dart';
import 'package:maqadi_v2/product_matching_v2/engine/candidate_text_normalizer.dart';
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
