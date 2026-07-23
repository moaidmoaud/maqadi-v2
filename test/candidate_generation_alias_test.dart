import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching_v2/application/candidate_generation_service.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_catalog_entry.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_evidence.dart';
import 'package:maqadi_v2/product_matching_v2/domain/product_match_trace.dart';
import 'package:maqadi_v2/product_matching_v2/engine/candidate_text_normalizer.dart';
import 'package:maqadi_v2/product_matching_v2/infrastructure/catalog_product_candidate_catalog.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  final line =
      const ReceiptLineBuilderEngine().build(productRow()).lines.single;

  test('canonical name is searched before aliases', () async {
    ProductMatchTrace? trace;
    final service = _service(
      query: 'ثوم',
      entries: [
        _entry('garlic', 'ثوم', aliases: const ['garlic'])
      ],
      onTrace: (value) => trace = value,
    );

    final candidate = (await service.generate(line)).single;

    expect(candidate.displayName, 'ثوم');
    expect(
      candidate.evidence.discoverySource,
      ProductMatchDiscoverySource.catalogName,
    );
    expect(candidate.evidence.matchedCatalogText, 'ثوم');
    expect(candidate.evidence.matchedAlias, isNull);
    expect(trace!.winningCandidate, isNull);
    expect(trace!.candidateRanking, isEmpty);
  });

  test('English alias discovers an Arabic canonical product', () async {
    final service = _service(
      query: 'Garlic Bag',
      entries: [
        _entry('garlic', 'ثوم', aliases: const ['garlic bag'])
      ],
    );

    final candidate = (await service.generate(line)).single;

    expect(candidate.productId, 'garlic');
    expect(candidate.displayName, 'ثوم');
    expect(
      candidate.evidence.discoverySource,
      ProductMatchDiscoverySource.catalogAlias,
    );
    expect(candidate.evidence.matchedAlias, 'garlic bag');
  });

  test('searches every explicit alias', () async {
    final entry = _entry(
      'potato',
      'بطاطس',
      aliases: const ['potato', 'potato bag', 'potatoes bag'],
    );

    for (final query in ['potato', 'potato bag', 'potatoes bag']) {
      final candidates = await _service(
        query: query,
        entries: [entry],
      ).generate(line);
      expect(candidates.single.productId, 'potato', reason: query);
      expect(candidates.single.evidence.matchedAlias, query, reason: query);
    }
  });

  test('duplicate aliases never duplicate a product candidate', () async {
    ProductMatchTrace? trace;
    final entry = ProductCatalogEntry(
      id: 'garlic',
      displayName: 'ثوم',
      normalizedCanonicalName: 'ثوم',
      aliases: const ['garlic', 'GARLIC', 'garlic'],
      normalizedAliasIndex: const {
        'garlic': ['garlic', 'GARLIC', 'garlic'],
      },
    );
    final service = _service(
      query: 'garlic',
      entries: [entry],
      onTrace: (value) => trace = value,
    );

    final candidates = await service.generate(line);

    expect(candidates, hasLength(1));
    expect(trace!.generatedCandidateIds, ['garlic']);
    expect(trace!.discoveryEvidence['garlic']!.matchedAlias, 'garlic');
  });

  test('Arabic-only products remain discoverable without translation',
      () async {
    final entry = _entry('salt', 'ملح');

    final arabicCandidates = await _service(
      query: 'ملح',
      entries: [entry],
    ).generate(line);
    final englishCandidates = await _service(
      query: 'salt',
      entries: [entry],
    ).generate(line);

    expect(arabicCandidates.single.productId, 'salt');
    expect(englishCandidates, isEmpty);
  });

  test('runtime catalog adapter provides explicit English bridge aliases',
      () async {
    final entries = await const CatalogProductCandidateCatalog().readProducts();
    final garlic = entries.singleWhere((value) => value.displayName == 'ثوم');
    final potatoes =
        entries.singleWhere((value) => value.displayName == 'بطاطس');
    final cream =
        entries.singleWhere((value) => value.displayName == 'كريمة طبخ');

    expect(garlic.normalizedCanonicalName, 'ثوم');
    expect(garlic.aliases, containsAll(['garlic', 'garlic bag']));
    expect(garlic.normalizedAliasIndex['garlic bag'], ['garlic bag']);
    expect(potatoes.aliases, contains('potatoes bag'));
    expect(cream.aliases, contains('puck cooking cream'));
  });

  test('runtime bridge discovers DAN-0001 English receipt products', () async {
    final cases = <(String, String, String)>[
      ('GÄRLIC -BAG', 'ثوم', 'garlic bag'),
      ('PÖTATOES -BAG', 'بطاطس', 'potatoes bag'),
      ('PUCK C0OKING CREAM', 'كريمة طبخ', 'puck cooking cream'),
    ];

    for (final (query, canonicalName, matchedAlias) in cases) {
      final candidates = await CandidateGenerationService(
        catalog: const CatalogProductCandidateCatalog(),
        textResolver: _Resolver(query),
      ).generate(line);
      final candidate =
          candidates.singleWhere((value) => value.displayName == canonicalName);

      expect(candidate.evidence.matchedAlias, matchedAlias, reason: query);
      expect(
        candidate.evidence.discoverySource,
        ProductMatchDiscoverySource.catalogAlias,
        reason: query,
      );
      expect(candidate.matchingScore, 0, reason: query);
      expect(candidate.confidence, 0, reason: query);
    }
  });

  test('catalog entries serialize normalized alias data immutably', () {
    final entry = _entry(
      'cream',
      'كريمة طبخ',
      aliases: const ['cooking cream', 'puck cooking cream'],
    );

    final restored = ProductCatalogEntry.fromJson(entry.toJson());

    expect(restored.toJson(), entry.toJson());
    expect(restored.normalizedCanonicalName, 'كريمة طبخ');
    expect(
      restored.normalizedAliasIndex['puck cooking cream'],
      ['puck cooking cream'],
    );
    expect(() => restored.aliases.add('other'), throwsUnsupportedError);
    expect(
      () => restored.normalizedAliasIndex['cooking cream']!.add('other'),
      throwsUnsupportedError,
    );
  });

  test('trace serializes the exact matched alias and discovery source',
      () async {
    ProductMatchTrace? trace;
    final service = _service(
      query: 'PUCK C0OKING CREAM',
      entries: [
        _entry(
          'cream',
          'كريمة طبخ',
          aliases: const ['puck cooking cream'],
        ),
      ],
      onTrace: (value) => trace = value,
    );

    await service.generate(line);
    final restored = ProductMatchTrace.fromJson(trace!.toJson());
    final evidence = restored.discoveryEvidence['cream']!;

    expect(evidence.discoverySource, ProductMatchDiscoverySource.catalogAlias);
    expect(evidence.matchedCatalogText, 'puck cooking cream');
    expect(evidence.matchedAlias, 'puck cooking cream');
    expect(restored.candidateRanking, isEmpty);
    expect(restored.winningCandidate, isNull);
  });
}

CandidateGenerationService _service({
  required String query,
  required List<ProductCatalogEntry> entries,
  ProductMatchTraceCallback? onTrace,
}) =>
    CandidateGenerationService(
      catalog: _Catalog(entries),
      textResolver: _Resolver(query),
      onTrace: onTrace,
    );

ProductCatalogEntry _entry(
  String id,
  String displayName, {
  List<String> aliases = const [],
}) {
  const normalizer = CandidateTextNormalizer();
  final index = <String, List<String>>{};
  for (final alias in aliases) {
    final normalized = normalizer.normalize(alias);
    index.putIfAbsent(normalized, () => <String>[]).add(alias);
  }
  return ProductCatalogEntry(
    id: id,
    displayName: displayName,
    normalizedCanonicalName: normalizer.normalize(displayName),
    aliases: aliases,
    normalizedAliasIndex: index,
  );
}

class _Catalog implements ProductCandidateCatalog {
  const _Catalog(this.entries);

  final List<ProductCatalogEntry> entries;

  @override
  Future<List<ProductCatalogEntry>> readProducts() async => entries;
}

class _Resolver implements ReceiptLineProductTextResolver {
  const _Resolver(this.query);

  final String query;

  @override
  Future<String?> resolve(ReceiptLine line) async => query;
}
