class ProductCatalogEntry {
  ProductCatalogEntry({
    required this.id,
    required this.displayName,
    this.normalizedCanonicalName = '',
    Iterable<String> aliases = const [],
    Map<String, Iterable<String>> normalizedAliasIndex = const {},
  })  : aliases = List.unmodifiable(aliases),
        normalizedAliasIndex = Map.unmodifiable({
          for (final entry in normalizedAliasIndex.entries)
            entry.key: List<String>.unmodifiable(entry.value),
        });

  factory ProductCatalogEntry.fromJson(Map<String, Object?> json) =>
      ProductCatalogEntry(
        id: json['id']! as String,
        displayName: json['displayName']! as String,
        normalizedCanonicalName:
            json['normalizedCanonicalName'] as String? ?? '',
        aliases: (json['aliases'] as List<Object?>? ?? const []).cast(),
        normalizedAliasIndex:
            (json['normalizedAliasIndex'] as Map<Object?, Object?>? ?? const {})
                .map(
          (key, value) => MapEntry(
            key! as String,
            (value! as List<Object?>).cast<String>(),
          ),
        ),
      );

  final String id;
  final String displayName;
  final String normalizedCanonicalName;
  final List<String> aliases;
  final Map<String, List<String>> normalizedAliasIndex;

  Map<String, Object> toJson() => {
        'id': id,
        'displayName': displayName,
        'normalizedCanonicalName': normalizedCanonicalName,
        'aliases': aliases,
        'normalizedAliasIndex': normalizedAliasIndex,
      };
}
