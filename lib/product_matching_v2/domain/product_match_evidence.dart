enum ProductMatchDiscoverySource { catalogName, catalogAlias }

class ProductMatchEvidence {
  ProductMatchEvidence({
    required this.normalizedQuery,
    required this.normalizedCatalogText,
    required Iterable<String> matchedTokens,
    required this.exactNormalizedMatch,
    required this.discoverySource,
    this.matchedCatalogText,
    this.matchedAlias,
  }) : matchedTokens = List.unmodifiable(matchedTokens);

  factory ProductMatchEvidence.fromJson(Map<String, Object?> json) =>
      ProductMatchEvidence(
        normalizedQuery: json['normalizedQuery']! as String,
        normalizedCatalogText: json['normalizedCatalogText']! as String,
        matchedTokens: (json['matchedTokens']! as List<Object?>).cast(),
        exactNormalizedMatch: json['exactNormalizedMatch']! as bool,
        discoverySource: ProductMatchDiscoverySource.values.byName(
          json['discoverySource']! as String,
        ),
        matchedCatalogText: json['matchedCatalogText'] as String?,
        matchedAlias: json['matchedAlias'] as String?,
      );

  final String normalizedQuery;
  final String normalizedCatalogText;
  final List<String> matchedTokens;
  final bool exactNormalizedMatch;
  final ProductMatchDiscoverySource discoverySource;
  final String? matchedCatalogText;
  final String? matchedAlias;

  Map<String, Object?> toJson() => {
        'normalizedQuery': normalizedQuery,
        'normalizedCatalogText': normalizedCatalogText,
        'matchedTokens': matchedTokens,
        'exactNormalizedMatch': exactNormalizedMatch,
        'discoverySource': discoverySource.name,
        'matchedCatalogText': matchedCatalogText,
        'matchedAlias': matchedAlias,
      };
}
