import '../../products.dart';
import '../application/candidate_generation_service.dart';
import '../domain/product_catalog_entry.dart';

class CatalogProductCandidateCatalog implements ProductCandidateCatalog {
  const CatalogProductCandidateCatalog();

  @override
  Future<List<ProductCatalogEntry>> readProducts() async => [
        for (var index = 0; index < products.length; index++)
          ProductCatalogEntry(
            id: 'catalog-$index',
            displayName: products[index].name,
            aliases: products[index].aliases,
          ),
      ];
}
