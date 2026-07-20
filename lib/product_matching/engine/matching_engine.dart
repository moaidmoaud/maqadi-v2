import '../domain/matching_failure.dart';
import '../domain/product_match_models.dart';
import '../domain/product_matching_repository.dart';
import 'matching_strategies.dart';
import 'matching_strategy.dart';
import 'text_normalizer.dart';

class MatchingEngine {
  const MatchingEngine({
    required ProductMatchingRepository repository,
    TextNormalizer normalizer = const TextNormalizer(),
    List<MatchingStrategy> strategies = const [
      ExactMatchStrategy(),
      NormalizedMatchStrategy(),
      AliasMatchStrategy(),
      FuzzyMatchStrategy(),
    ],
  })  : _repository = repository,
        _normalizer = normalizer,
        _strategies = strategies;

  final ProductMatchingRepository _repository;
  final TextNormalizer _normalizer;
  final List<MatchingStrategy> _strategies;

  List<String> sourceTexts(
    ProductMatchRequest request, {
    bool includeExcluded = false,
  }) {
    final structuredLines = <String>[
      for (final block in request.ocrResult.blocks)
        for (final line in block.lines) line.text,
    ];
    final rawTexts = structuredLines.isNotEmpty
        ? structuredLines
        : request.ocrResult.text.split(RegExp(r'\r?\n'));
    final excluded = request.excludedSourceTexts
        .map(_normalizer.normalize)
        .where((text) => text.isNotEmpty)
        .toSet();
    final seen = <String>{};
    final result = <String>[];
    for (final rawText in rawTexts) {
      final text = rawText.trim();
      final normalized = _normalizer.normalize(text);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      if (!includeExcluded && excluded.contains(normalized)) continue;
      result.add(text);
    }
    return result;
  }

  Future<ProductMatchResult> match(
    ProductMatchRequest request, {
    List<String>? sourceOverride,
  }) async {
    final products = await _repository.readProducts();
    final sources = sourceOverride ?? sourceTexts(request);
    final bestByProduct = <String, MatchCandidate>{};
    var generatedCandidateCount = 0;

    for (final sourceText in sources) {
      final normalizedSource = _normalizer.normalize(sourceText);
      if (normalizedSource.isEmpty) continue;
      for (final product in products) {
        final normalizedProduct = _normalizer.normalize(product.name);
        final normalizedAliases = {
          for (final alias in product.aliases)
            alias: _normalizer.normalize(alias),
        };
        final context = MatchingContext(
          sourceText: sourceText,
          normalizedSourceText: normalizedSource,
          product: product,
          normalizedProductText: normalizedProduct,
          normalizedAliases: normalizedAliases,
        );
        for (final strategy in _strategies) {
          final evaluation = strategy.evaluate(context);
          if (evaluation == null) continue;
          generatedCandidateCount++;
          final confidenceValue =
              evaluation.confidence.clamp(0.0, 1.0).toDouble();
          if (confidenceValue < request.minimumConfidence) break;
          final confidence = MatchConfidence(confidenceValue);
          final explanation = MatchExplanation(
            strategy: strategy.type,
            normalizedOcrText: normalizedSource,
            normalizedProductText: normalizedProduct,
            matchedAlias: evaluation.matchedAlias,
            similarityScore:
                evaluation.similarityScore.clamp(0.0, 1.0).toDouble(),
            finalConfidence: confidence,
            summary: _summary(strategy.type, evaluation.matchedAlias),
          );
          final candidate = MatchCandidate(
            product: product,
            matchedText: sourceText,
            confidence: confidence,
            strategy: strategy.type,
            explanation: explanation,
          );
          final existing = bestByProduct[product.id];
          if (existing == null || _isBetter(candidate, existing)) {
            bestByProduct[product.id] = candidate;
          }
          break;
        }
      }
    }

    final matches = bestByProduct.values
        .map(
          (candidate) => MatchedProduct(
            product: candidate.product,
            confidence: candidate.confidence,
            matchedStrategy: candidate.strategy,
            matchedText: candidate.matchedText,
            explanation: candidate.explanation,
          ),
        )
        .toList()
      ..sort(_compareMatches);
    if (matches.isEmpty) {
      throw const NoCandidatesFound('لم يتم العثور على منتجات مطابقة.');
    }
    return ProductMatchResult(
      matches: matches.take(request.maximumResults).toList(growable: false),
      generatedCandidateCount: generatedCandidateCount,
      evaluatedSourceCount: sources.length,
    );
  }

  bool _isBetter(MatchCandidate candidate, MatchCandidate existing) {
    final confidenceComparison = candidate.confidence.value.compareTo(
      existing.confidence.value,
    );
    if (confidenceComparison != 0) return confidenceComparison > 0;
    return _strategyPriority(candidate.strategy) <
        _strategyPriority(existing.strategy);
  }

  int _compareMatches(MatchedProduct left, MatchedProduct right) {
    final confidence = right.confidence.value.compareTo(left.confidence.value);
    if (confidence != 0) return confidence;
    final strategy = _strategyPriority(left.matchedStrategy).compareTo(
      _strategyPriority(right.matchedStrategy),
    );
    if (strategy != 0) return strategy;
    return left.product.name.compareTo(right.product.name);
  }

  int _strategyPriority(MatchingStrategyType type) {
    final index = _strategies.indexWhere((strategy) => strategy.type == type);
    return index < 0 ? _strategies.length : index;
  }

  String _summary(MatchingStrategyType type, String? alias) => switch (type) {
        MatchingStrategyType.exact => 'تطابق النص الأصلي مع اسم المنتج.',
        MatchingStrategyType.normalized =>
          'تطابق النص بعد توحيد الأحرف والمسافات وعلامات الترقيم.',
        MatchingStrategyType.alias =>
          'تطابق النص مع الاسم البديل${alias == null ? '' : ' "$alias"'}.',
        MatchingStrategyType.fuzzy =>
          'تقارب النص مع اسم المنتج وفق تشابه الأحرف.',
      };
}
