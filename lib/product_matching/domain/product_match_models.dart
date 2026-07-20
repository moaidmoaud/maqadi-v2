import '../../receipt_ocr/domain/receipt_ocr_result.dart';

enum MatchingStrategyType { exact, normalized, alias, fuzzy }

class MatchConfidence {
  const MatchConfidence(this.value)
      : assert(value >= 0 && value <= 1, 'Confidence must be between 0 and 1.');

  final double value;
}

class MatchableProduct {
  const MatchableProduct({
    required this.id,
    required this.name,
    required this.category,
    this.aliases = const [],
  });

  final String id;
  final String name;
  final String category;
  final List<String> aliases;
}

class MatchExplanation {
  const MatchExplanation({
    required this.strategy,
    required this.normalizedOcrText,
    required this.normalizedProductText,
    required this.similarityScore,
    required this.finalConfidence,
    this.matchedAlias,
    this.summary,
  });

  final MatchingStrategyType strategy;
  final String normalizedOcrText;
  final String normalizedProductText;
  final String? matchedAlias;
  final double similarityScore;
  final MatchConfidence finalConfidence;
  final String? summary;
}

class MatchCandidate {
  const MatchCandidate({
    required this.product,
    required this.matchedText,
    required this.confidence,
    required this.strategy,
    required this.explanation,
  });

  final MatchableProduct product;
  final String matchedText;
  final MatchConfidence confidence;
  final MatchingStrategyType strategy;
  final MatchExplanation explanation;
}

class MatchedProduct {
  const MatchedProduct({
    required this.product,
    required this.confidence,
    required this.matchedStrategy,
    required this.matchedText,
    required this.explanation,
  });

  final MatchableProduct product;
  final MatchConfidence confidence;
  final MatchingStrategyType matchedStrategy;
  final String matchedText;
  final MatchExplanation explanation;
}

class ProductMatchRequest {
  const ProductMatchRequest({
    required this.ocrResult,
    this.minimumConfidence = 0.55,
    this.maximumResults = 10,
    this.excludedSourceTexts = const {},
  });

  final ReceiptOcrResult ocrResult;
  final double minimumConfidence;
  final int maximumResults;
  final Set<String> excludedSourceTexts;

  ProductMatchRequest copyWith({Set<String>? excludedSourceTexts}) =>
      ProductMatchRequest(
        ocrResult: ocrResult,
        minimumConfidence: minimumConfidence,
        maximumResults: maximumResults,
        excludedSourceTexts: excludedSourceTexts ?? this.excludedSourceTexts,
      );
}

class ProductMatchResult {
  const ProductMatchResult({
    required this.matches,
    required this.generatedCandidateCount,
    required this.evaluatedSourceCount,
  });

  final List<MatchedProduct> matches;
  final int generatedCandidateCount;
  final int evaluatedSourceCount;
}
