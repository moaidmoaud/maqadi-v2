import '../domain/product_match_models.dart';
import 'matching_strategy.dart';

class ExactMatchStrategy implements MatchingStrategy {
  const ExactMatchStrategy();

  @override
  MatchingStrategyType get type => MatchingStrategyType.exact;

  @override
  StrategyEvaluation? evaluate(MatchingContext context) =>
      context.sourceText.trim() == context.product.name.trim()
          ? const StrategyEvaluation(similarityScore: 1, confidence: 1)
          : null;
}

class NormalizedMatchStrategy implements MatchingStrategy {
  const NormalizedMatchStrategy();

  @override
  MatchingStrategyType get type => MatchingStrategyType.normalized;

  @override
  StrategyEvaluation? evaluate(MatchingContext context) {
    final source = context.normalizedSourceText;
    final product = context.normalizedProductText;
    if (source == product) {
      return const StrategyEvaluation(similarityScore: 1, confidence: 0.96);
    }
    if (_containsPhrase(source, product)) {
      final similarity = _lengthRatio(product, source);
      return StrategyEvaluation(
        similarityScore: similarity,
        confidence: 0.88 + (similarity * 0.08),
      );
    }
    return null;
  }
}

class AliasMatchStrategy implements MatchingStrategy {
  const AliasMatchStrategy();

  @override
  MatchingStrategyType get type => MatchingStrategyType.alias;

  @override
  StrategyEvaluation? evaluate(MatchingContext context) {
    for (final alias in context.normalizedAliases.entries) {
      if (context.normalizedSourceText == alias.value) {
        return StrategyEvaluation(
          similarityScore: 1,
          confidence: 0.92,
          matchedAlias: alias.key,
        );
      }
      if (_containsPhrase(context.normalizedSourceText, alias.value)) {
        return StrategyEvaluation(
          similarityScore: _lengthRatio(
            alias.value,
            context.normalizedSourceText,
          ),
          confidence: 0.86,
          matchedAlias: alias.key,
        );
      }
    }
    return null;
  }
}

class FuzzyMatchStrategy implements MatchingStrategy {
  const FuzzyMatchStrategy({this.minimumSimilarity = 0.65});

  final double minimumSimilarity;

  @override
  MatchingStrategyType get type => MatchingStrategyType.fuzzy;

  @override
  StrategyEvaluation? evaluate(MatchingContext context) {
    var bestSimilarity = _similarity(
      context.normalizedSourceText,
      context.normalizedProductText,
    );
    String? matchedAlias;
    for (final alias in context.normalizedAliases.entries) {
      final similarity = _similarity(context.normalizedSourceText, alias.value);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        matchedAlias = alias.key;
      }
    }
    if (bestSimilarity < minimumSimilarity) return null;
    return StrategyEvaluation(
      similarityScore: bestSimilarity,
      confidence: 0.55 + (bestSimilarity * 0.35),
      matchedAlias: matchedAlias,
    );
  }
}

bool _containsPhrase(String source, String phrase) {
  if (phrase.isEmpty) return false;
  return source == phrase ||
      source.startsWith('$phrase ') ||
      source.endsWith(' $phrase') ||
      source.contains(' $phrase ');
}

double _lengthRatio(String shorter, String longer) {
  if (longer.isEmpty) return 0;
  return (shorter.runes.length / longer.runes.length)
      .clamp(0.0, 1.0)
      .toDouble();
}

double _similarity(String left, String right) {
  if (left.isEmpty || right.isEmpty) return 0;
  if (left == right) return 1;
  final leftRunes = left.runes.toList(growable: false);
  final rightRunes = right.runes.toList(growable: false);
  var previous = List<int>.generate(rightRunes.length + 1, (index) => index);
  for (var leftIndex = 0; leftIndex < leftRunes.length; leftIndex++) {
    final current = <int>[leftIndex + 1];
    for (var rightIndex = 0; rightIndex < rightRunes.length; rightIndex++) {
      final substitutionCost =
          leftRunes[leftIndex] == rightRunes[rightIndex] ? 0 : 1;
      current.add(
        _minimum(
          current[rightIndex] + 1,
          previous[rightIndex + 1] + 1,
          previous[rightIndex] + substitutionCost,
        ),
      );
    }
    previous = current;
  }
  final longest = leftRunes.length > rightRunes.length
      ? leftRunes.length
      : rightRunes.length;
  return 1 - (previous.last / longest);
}

int _minimum(int first, int second, int third) {
  var result = first < second ? first : second;
  if (third < result) result = third;
  return result;
}
