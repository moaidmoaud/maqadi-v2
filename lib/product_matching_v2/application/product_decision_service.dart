import '../domain/product_match_result.dart';
import '../engine/product_decision_engine.dart';

class ProductDecisionService {
  const ProductDecisionService({
    ProductDecisionEngine engine = const ProductDecisionEngine(),
  }) : _engine = engine;

  final ProductDecisionEngine _engine;

  ProductMatchResult decide(ProductMatchResult ranked) =>
      _engine.decide(ranked);
}
