import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching/application/product_matching_service.dart';
import 'package:maqadi_v2/product_matching/domain/matching_failure.dart';
import 'package:maqadi_v2/product_matching/domain/product_match_models.dart';
import 'package:maqadi_v2/product_matching/domain/product_matching_repository.dart';
import 'package:maqadi_v2/product_matching/engine/matching_engine.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';

void main() {
  group('ProductMatchingService', () {
    test('creates an exact match with a structured explanation', () async {
      final result = await _service().match(_request(['Fresh Milk']));
      final match = result.matches.single;

      expect(match.product.id, 'milk');
      expect(match.confidence.value, 1);
      expect(match.matchedStrategy, MatchingStrategyType.exact);
      expect(match.explanation.strategy, MatchingStrategyType.exact);
      expect(match.explanation.normalizedOcrText, 'fresh milk');
      expect(match.explanation.normalizedProductText, 'fresh milk');
      expect(match.explanation.finalConfidence, same(match.confidence));
      expect(match.explanation.summary, isNotEmpty);
    });

    test('generates normalized match explanation', () async {
      final match =
          (await _service().match(_request(['FRESH, MILK!']))).matches.single;

      expect(match.matchedStrategy, MatchingStrategyType.normalized);
      expect(match.explanation.similarityScore, 1);
      expect(match.explanation.matchedAlias, isNull);
    });

    test('generates alias match explanation', () async {
      final match = (await _service().match(_request(['حليب']))).matches.single;

      expect(match.matchedStrategy, MatchingStrategyType.alias);
      expect(match.explanation.matchedAlias, 'حليب');
      expect(match.explanation.finalConfidence.value, 0.92);
    });

    test('generates fuzzy match explanation', () async {
      final match =
          (await _service().match(_request(['Fresh Mik']))).matches.single;

      expect(match.matchedStrategy, MatchingStrategyType.fuzzy);
      expect(match.explanation.similarityScore, greaterThan(0.8));
      expect(match.explanation.finalConfidence.value, inInclusiveRange(0, 1));
    });

    test('generates and ranks multiple candidates by confidence', () async {
      final result = await _service().match(
        _request(['Fresh Mik', 'Brown Bread', 'Apple Juc']),
      );

      expect(result.matches, hasLength(3));
      expect(result.matches.first.product.id, 'bread');
      expect(result.matches.first.confidence.value, 1);
      for (var index = 1; index < result.matches.length; index++) {
        expect(
          result.matches[index - 1].confidence.value,
          greaterThanOrEqualTo(result.matches[index].confidence.value),
        );
      }
      expect(result.generatedCandidateCount, greaterThanOrEqualTo(3));
      expect(result.evaluatedSourceCount, 3);
    });

    test('limits ranked results only after generating candidates', () async {
      final result = await _service().match(
        _request(['Fresh Milk', 'Brown Bread'], maximumResults: 1),
      );

      expect(result.matches, hasLength(1));
      expect(result.generatedCandidateCount, 2);
    });

    test('does not accept matches below the requested confidence', () async {
      await expectLater(
        _service().match(_request(['Fresh Mik'], minimumConfidence: 0.95)),
        throwsA(isA<NoCandidatesFound>()),
      );
    });

    test('rejects empty OCR input before reading products', () async {
      final repository = _MockProductRepository(_products);

      await expectLater(
        _service(repository).match(_request([])),
        throwsA(isA<InvalidProductMatchRequest>()),
      );
      expect(repository.readCalls, 0);
    });

    test('reports no candidates for unrelated OCR text', () async {
      await expectLater(
        _service().match(_request(['receipt total 25.00'])),
        throwsA(isA<NoCandidatesFound>()),
      );
    });

    test('maps repository failures without leaking repository exceptions',
        () async {
      final repository = _MockProductRepository(_products)
        ..error = const ProductMatchingRepositoryException('catalog failed');

      await expectLater(
        _service(repository).match(_request(['Fresh Milk'])),
        throwsA(
          isA<ProductMatchingRepositoryFailure>().having(
            (failure) => failure.message,
            'message',
            'catalog failed',
          ),
        ),
      );
    });

    test('maps unexpected failures to matching failed', () async {
      final repository = _MockProductRepository(_products)
        ..error = StateError('unexpected');

      await expectLater(
        _service(repository).match(_request(['Fresh Milk'])),
        throwsA(isA<ProductMatchingFailed>()),
      );
    });

    test('manual search uses the same matching pipeline', () async {
      final result = await _service().searchManually(
        _request(['unknown']),
        'Brown Bread',
      );

      expect(result.matches.single.product.id, 'bread');
      expect(result.matches.single.matchedStrategy, MatchingStrategyType.exact);
    });

    test('excluded OCR lines are not evaluated', () async {
      final request = ProductMatchRequest(
        ocrResult: _ocrResult(['Fresh Milk', 'Brown Bread']),
        excludedSourceTexts: const {'Fresh Milk'},
      );

      final result = await _service().match(request);

      expect(result.matches.single.product.id, 'bread');
      expect(result.evaluatedSourceCount, 1);
    });

    test('validates confidence and result limits', () async {
      await expectLater(
        _service().match(_request(['Milk'], minimumConfidence: 1.1)),
        throwsA(isA<InvalidProductMatchRequest>()),
      );
      await expectLater(
        _service().match(_request(['Milk'], maximumResults: 0)),
        throwsA(isA<InvalidProductMatchRequest>()),
      );
    });
  });
}

ProductMatchingService _service([ProductMatchingRepository? repository]) =>
    ProductMatchingService(
      engine: MatchingEngine(
        repository: repository ?? _MockProductRepository(_products),
      ),
    );

ProductMatchRequest _request(
  List<String> lines, {
  double minimumConfidence = 0.55,
  int maximumResults = 10,
}) =>
    ProductMatchRequest(
      ocrResult: _ocrResult(lines),
      minimumConfidence: minimumConfidence,
      maximumResults: maximumResults,
    );

ReceiptOcrResult _ocrResult(List<String> lines) => ReceiptOcrResult(
      text: lines.join('\n'),
      blocks: lines.isEmpty
          ? const []
          : [
              ReceiptOcrBlock(
                text: lines.join('\n'),
                lines: [
                  for (final line in lines)
                    ReceiptOcrLine(text: line, words: const []),
                ],
              ),
            ],
    );

const _products = [
  MatchableProduct(
    id: 'milk',
    name: 'Fresh Milk',
    category: 'Dairy',
    aliases: ['حليب', 'Whole Milk'],
  ),
  MatchableProduct(
    id: 'bread',
    name: 'Brown Bread',
    category: 'Bakery',
    aliases: ['خبز'],
  ),
  MatchableProduct(
    id: 'juice',
    name: 'Apple Juice',
    category: 'Drinks',
    aliases: ['عصير تفاح'],
  ),
];

class _MockProductRepository implements ProductMatchingRepository {
  _MockProductRepository(this.products);

  final List<MatchableProduct> products;
  Object? error;
  int readCalls = 0;

  @override
  Future<List<MatchableProduct>> readProducts() async {
    readCalls++;
    if (error case final current?) throw current;
    return products;
  }
}
