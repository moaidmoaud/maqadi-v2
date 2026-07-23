import '../domain/product_match_result.dart';
import '../engine/product_ranking_engine.dart';

class ProductRankingService {
  const ProductRankingService({
    ProductRankingEngine engine = const ProductRankingEngine(),
  }) : _engine = engine;

  final ProductRankingEngine _engine;

  ProductMatchResult rank(ProductMatchResult input) => _engine.rank(input);
}
