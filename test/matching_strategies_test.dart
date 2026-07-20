import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching/domain/product_match_models.dart';
import 'package:maqadi_v2/product_matching/engine/matching_strategies.dart';
import 'package:maqadi_v2/product_matching/engine/matching_strategy.dart';
import 'package:maqadi_v2/product_matching/engine/text_normalizer.dart';

void main() {
  group('matching strategies', () {
    test('exact strategy accepts only the original product name', () {
      final evaluation = const ExactMatchStrategy().evaluate(
        _context('Fresh Milk', const _ProductFixture.freshMilk()),
      );

      expect(evaluation!.confidence, 1);
      expect(evaluation.similarityScore, 1);
      expect(
        const ExactMatchStrategy().evaluate(
          _context('fresh milk', const _ProductFixture.freshMilk()),
        ),
        isNull,
      );
    });

    test('normalized strategy handles case and punctuation', () {
      final evaluation = const NormalizedMatchStrategy().evaluate(
        _context('FRESH, MILK!', const _ProductFixture.freshMilk()),
      );

      expect(evaluation, isNotNull);
      expect(evaluation!.confidence, 0.96);
    });

    test('normalized strategy recognizes product within a receipt line', () {
      final evaluation = const NormalizedMatchStrategy().evaluate(
        _context('2 Fresh Milk 12.00', const _ProductFixture.freshMilk()),
      );

      expect(evaluation, isNotNull);
      expect(evaluation!.confidence, inInclusiveRange(0.88, 0.96));
    });

    test('alias strategy reports the original matched alias', () {
      final evaluation = const AliasMatchStrategy().evaluate(
        _context('حليب', const _ProductFixture.freshMilk()),
      );

      expect(evaluation!.matchedAlias, 'حليب');
      expect(evaluation.confidence, 0.92);
    });

    test('fuzzy strategy scores a typographical variation', () {
      final evaluation = const FuzzyMatchStrategy().evaluate(
        _context('Fresh Mik', const _ProductFixture.freshMilk()),
      );

      expect(evaluation, isNotNull);
      expect(evaluation!.similarityScore, greaterThan(0.8));
      expect(evaluation.confidence, inInclusiveRange(0.55, 1));
    });

    test('fuzzy strategy rejects unrelated text', () {
      expect(
        const FuzzyMatchStrategy().evaluate(
          _context('tomatoes', const _ProductFixture.freshMilk()),
        ),
        isNull,
      );
    });
  });
}

MatchingContext _context(String source, _ProductFixture fixture) {
  const normalizer = TextNormalizer();
  final product = fixture.product;
  return MatchingContext(
    sourceText: source,
    normalizedSourceText: normalizer.normalize(source),
    product: product,
    normalizedProductText: normalizer.normalize(product.name),
    normalizedAliases: {
      for (final alias in product.aliases) alias: normalizer.normalize(alias),
    },
  );
}

class _ProductFixture {
  const _ProductFixture.freshMilk()
      : product = const MatchableProduct(
          id: 'milk',
          name: 'Fresh Milk',
          category: 'Dairy',
          aliases: ['حليب', 'Whole Milk'],
        );

  final MatchableProduct product;
}
