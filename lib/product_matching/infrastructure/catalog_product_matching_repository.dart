import '../../products.dart';
import '../domain/product_match_models.dart';
import '../domain/product_matching_repository.dart';

class CatalogProductMatchingRepository implements ProductMatchingRepository {
  const CatalogProductMatchingRepository();

  @override
  Future<List<MatchableProduct>> readProducts() async => [
        for (var index = 0; index < products.length; index++)
          MatchableProduct(
            id: 'catalog-$index',
            name: products[index].name,
            category: products[index].category,
            aliases: products[index].aliases,
          ),
      ];
}
