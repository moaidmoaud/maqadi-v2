import '../domain/matching_failure.dart';
import '../domain/product_match_models.dart';
import '../domain/product_matching_repository.dart';
import '../engine/matching_engine.dart';

class ProductMatchingService {
  const ProductMatchingService({required MatchingEngine engine})
      : _engine = engine;

  final MatchingEngine _engine;

  List<String> sourceLines(ProductMatchRequest request) =>
      _engine.sourceTexts(request, includeExcluded: true);

  ProductMatchResult resultWithoutCandidates(ProductMatchRequest request) =>
      ProductMatchResult(
        matches: const [],
        generatedCandidateCount: 0,
        evaluatedSourceCount: _engine.sourceTexts(request).length,
      );

  Future<ProductMatchResult> match(ProductMatchRequest request) async {
    _validateSettings(request);
    if (request.ocrResult.text.trim().isEmpty &&
        _engine.sourceTexts(request, includeExcluded: true).isEmpty) {
      throw const InvalidProductMatchRequest(
        'نتيجة التعرف على النص فارغة.',
      );
    }
    return _execute(() => _engine.match(request));
  }

  Future<ProductMatchResult> searchManually(
    ProductMatchRequest request,
    String query,
  ) async {
    _validateSettings(request);
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      throw const InvalidProductMatchRequest('أدخل اسم منتج للبحث.');
    }
    return _execute(
      () => _engine.match(request, sourceOverride: [cleanQuery]),
    );
  }

  void _validateSettings(ProductMatchRequest request) {
    if (request.minimumConfidence < 0 || request.minimumConfidence > 1) {
      throw const InvalidProductMatchRequest(
        'حد الثقة يجب أن يكون بين صفر وواحد.',
      );
    }
    if (request.maximumResults <= 0) {
      throw const InvalidProductMatchRequest(
        'الحد الأقصى للنتائج يجب أن يكون أكبر من صفر.',
      );
    }
  }

  Future<ProductMatchResult> _execute(
    Future<ProductMatchResult> Function() operation,
  ) async {
    try {
      return await operation();
    } on MatchingFailure {
      rethrow;
    } on ProductMatchingRepositoryException catch (error) {
      throw ProductMatchingRepositoryFailure(
        error.message,
        cause: error.cause,
      );
    } catch (error) {
      throw ProductMatchingFailed(
        'تعذرت مطابقة المنتجات. حاول مجددًا.',
        cause: error,
      );
    }
  }
}
