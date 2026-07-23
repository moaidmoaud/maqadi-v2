import '../../products.dart';
import '../application/candidate_generation_service.dart';
import '../domain/product_catalog_entry.dart';
import '../engine/candidate_text_normalizer.dart';
import 'catalog_language_bridge.dart';

class CatalogProductCandidateCatalog implements ProductCandidateCatalog {
  const CatalogProductCandidateCatalog({
    CandidateTextNormalizer normalizer = const CandidateTextNormalizer(),
  }) : _normalizer = normalizer;

  final CandidateTextNormalizer _normalizer;

  @override
  Future<List<ProductCatalogEntry>> readProducts() async {
    final entries = <ProductCatalogEntry>[];
    for (var index = 0; index < products.length; index++) {
      final product = products[index];
      final aliases = _deduplicateAliases([
        ...product.aliases,
        ...?productCatalogLanguageBridge[product.name],
      ]);
      entries.add(ProductCatalogEntry(
        id: 'catalog-$index',
        displayName: product.name,
        normalizedCanonicalName: _normalizer.normalize(product.name),
        aliases: aliases,
        normalizedAliasIndex: _normalizedAliasIndex(aliases),
      ));
    }
    return List.unmodifiable(entries);
  }

  List<String> _deduplicateAliases(Iterable<String> aliases) {
    final seen = <String>{};
    final result = <String>[];
    for (final alias in aliases) {
      final normalized = _normalizer.normalize(alias);
      if (normalized.isNotEmpty && seen.add(normalized)) result.add(alias);
    }
    return List.unmodifiable(result);
  }

  Map<String, List<String>> _normalizedAliasIndex(Iterable<String> aliases) {
    final index = <String, List<String>>{};
    for (final alias in aliases) {
      final normalized = _normalizer.normalize(alias);
      if (normalized.isEmpty) continue;
      index.putIfAbsent(normalized, () => <String>[]).add(alias);
    }
    return index;
  }
}
