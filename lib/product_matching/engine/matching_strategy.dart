import '../domain/product_match_models.dart';

class MatchingContext {
  const MatchingContext({
    required this.sourceText,
    required this.normalizedSourceText,
    required this.product,
    required this.normalizedProductText,
    required this.normalizedAliases,
  });

  final String sourceText;
  final String normalizedSourceText;
  final MatchableProduct product;
  final String normalizedProductText;
  final Map<String, String> normalizedAliases;
}

class StrategyEvaluation {
  const StrategyEvaluation({
    required this.similarityScore,
    required this.confidence,
    this.matchedAlias,
  });

  final double similarityScore;
  final double confidence;
  final String? matchedAlias;
}

abstract interface class MatchingStrategy {
  MatchingStrategyType get type;

  StrategyEvaluation? evaluate(MatchingContext context);
}
