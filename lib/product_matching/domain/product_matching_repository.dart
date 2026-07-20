import 'product_match_models.dart';

abstract interface class ProductMatchingRepository {
  Future<List<MatchableProduct>> readProducts();
}

class ProductMatchingRepositoryException implements Exception {
  const ProductMatchingRepositoryException(this.message, {this.cause});

  final String message;
  final Object? cause;
}
