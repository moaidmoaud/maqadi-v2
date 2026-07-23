import '../../receipt_line_builder/domain/receipt_line.dart';
import '../domain/product_match_candidate.dart';
import '../domain/product_match_trace.dart';
import 'candidate_generation_service.dart';

class CandidateGenerationDebugCandidate {
  const CandidateGenerationDebugCandidate({
    required this.candidate,
    required this.evaluationOrder,
    required this.generationOrder,
  });

  final ProductMatchCandidate candidate;
  final int evaluationOrder;
  final int generationOrder;
}

class CandidateGenerationDebugLine {
  CandidateGenerationDebugLine({
    required this.receiptLineId,
    required this.originalProductText,
    required this.trace,
    required Iterable<CandidateGenerationDebugCandidate> candidates,
    Iterable<String> duplicateNormalizedQueryLineIds = const [],
  })  : candidates = List.unmodifiable(candidates),
        duplicateNormalizedQueryLineIds =
            List.unmodifiable(duplicateNormalizedQueryLineIds);

  final String receiptLineId;
  final String? originalProductText;
  final ProductMatchTrace trace;
  final List<CandidateGenerationDebugCandidate> candidates;
  final List<String> duplicateNormalizedQueryLineIds;

  bool get hasDuplicateNormalizedQuery =>
      duplicateNormalizedQueryLineIds.length > 1;
}

class CandidateGenerationDebugService {
  const CandidateGenerationDebugService({
    required ProductCandidateCatalog catalog,
    required ReceiptLineProductTextResolver textResolver,
  })  : _catalog = catalog,
        _textResolver = textResolver;

  final ProductCandidateCatalog _catalog;
  final ReceiptLineProductTextResolver _textResolver;

  Future<List<CandidateGenerationDebugLine>> inspect(
    List<ReceiptLine> lines,
  ) async {
    final inspected = <CandidateGenerationDebugLine>[];
    for (final line in lines) {
      final originalText = await _textResolver.resolve(line);
      ProductMatchTrace? trace;
      final generator = CandidateGenerationService(
        catalog: _catalog,
        textResolver: _ResolvedTextResolver(originalText),
        onTrace: (value) => trace = value,
      );
      final generated = await generator.generate(line);
      final generatedTrace = trace!;
      final candidates = <CandidateGenerationDebugCandidate>[];
      for (var index = 0; index < generated.length; index++) {
        final candidate = generated[index];
        candidates.add(CandidateGenerationDebugCandidate(
          candidate: candidate,
          evaluationOrder:
              generatedTrace.evaluationOrder.indexOf(candidate.productId) + 1,
          generationOrder: index + 1,
        ));
      }
      inspected.add(CandidateGenerationDebugLine(
        receiptLineId: line.id,
        originalProductText: originalText,
        trace: generatedTrace,
        candidates: candidates,
      ));
    }
    final lineIdsByQuery = <String, List<String>>{};
    for (final result in inspected) {
      final query = result.trace.normalizedQuery ?? '';
      if (query.isEmpty) continue;
      lineIdsByQuery.putIfAbsent(query, () => <String>[]).add(
            result.receiptLineId,
          );
    }
    return List.unmodifiable([
      for (final result in inspected)
        CandidateGenerationDebugLine(
          receiptLineId: result.receiptLineId,
          originalProductText: result.originalProductText,
          trace: result.trace,
          candidates: result.candidates,
          duplicateNormalizedQueryLineIds:
              lineIdsByQuery[result.trace.normalizedQuery] ?? const [],
        ),
    ]);
  }
}

class _ResolvedTextResolver implements ReceiptLineProductTextResolver {
  const _ResolvedTextResolver(this.value);

  final String? value;

  @override
  Future<String?> resolve(ReceiptLine line) async => value;
}
