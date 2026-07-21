import 'shopping_recommendation.dart';
import 'shopping_recommendation_explanation.dart';
import 'shopping_recommendation_failure.dart';

class ShoppingRecommendationResult {
  const ShoppingRecommendationResult({
    required this.productId,
    required this.productName,
    required this.category,
    required this.recommendation,
    required this.explanation,
  });

  final String productId;
  final String productName;
  final String category;
  final ShoppingRecommendation recommendation;
  final ShoppingRecommendationExplanation explanation;
}

sealed class ShoppingRecommendationItemEvaluation {
  const ShoppingRecommendationItemEvaluation();
}

class ShoppingRecommendationItemSuccess
    extends ShoppingRecommendationItemEvaluation {
  const ShoppingRecommendationItemSuccess(this.result);

  final ShoppingRecommendationResult result;
}

class ShoppingRecommendationItemFailure
    extends ShoppingRecommendationItemEvaluation {
  const ShoppingRecommendationItemFailure(this.failure);

  final ShoppingRecommendationFailure failure;
}

sealed class ShoppingRecommendationEvaluation {
  const ShoppingRecommendationEvaluation();
}

class ShoppingRecommendationEvaluationSuccess
    extends ShoppingRecommendationEvaluation {
  ShoppingRecommendationEvaluationSuccess({
    required Iterable<ShoppingRecommendationResult> results,
    required Map<String, ShoppingRecommendationFailure> failures,
  })  : results = List.unmodifiable(results),
        failures = Map.unmodifiable(failures);

  final List<ShoppingRecommendationResult> results;
  final Map<String, ShoppingRecommendationFailure> failures;
}

class ShoppingRecommendationEvaluationFailure
    extends ShoppingRecommendationEvaluation {
  const ShoppingRecommendationEvaluationFailure(this.failure);

  final ShoppingRecommendationFailure failure;
}
