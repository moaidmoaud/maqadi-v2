class ProductCatalogEntry {
  ProductCatalogEntry({
    required this.id,
    required this.displayName,
    Iterable<String> aliases = const [],
  }) : aliases = List.unmodifiable(aliases);

  final String id;
  final String displayName;
  final List<String> aliases;
}
