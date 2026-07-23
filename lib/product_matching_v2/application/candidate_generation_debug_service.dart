import '../../receipt_line_builder/domain/receipt_line.dart';
import '../domain/product_match_candidate.dart';
import '../domain/product_match_reason.dart';
import '../domain/product_match_result.dart';
import '../domain/product_match_trace.dart';
import '../domain/product_ranking_evidence.dart';
import 'candidate_generation_service.dart';
import 'product_decision_service.dart';
import 'product_ranking_service.dart';

class CandidateGenerationDebugCandidate {
  const CandidateGenerationDebugCandidate({
    required this.candidate,
    required this.evaluationOrder,
    required this.generationOrder,
    required this.rank,
    required this.rankingEvidence,
  });

  final ProductMatchCandidate candidate;
  final int evaluationOrder;
  final int generationOrder;
  final int rank;
  final ProductCandidateRankingEvidence rankingEvidence;
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
    ProductRankingService rankingService = const ProductRankingService(),
    ProductDecisionService decisionService = const ProductDecisionService(),
  })  : _catalog = catalog,
        _textResolver = textResolver,
        _rankingService = rankingService,
        _decisionService = decisionService;

  final ProductCandidateCatalog _catalog;
  final ReceiptLineProductTextResolver _textResolver;
  final ProductRankingService _rankingService;
  final ProductDecisionService _decisionService;

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
      final ranked = _rankingService.rank(ProductMatchResult(
        receiptLineId: line.id,
        matchedProduct: null,
        candidates: generated,
        finalConfidence: null,
        status: ProductMatchStatus.pending,
        decisionReason: ProductMatchReason.notEvaluated,
        trace: generatedTrace,
      ));
      final decided = _decisionService.decide(ranked);
      final decidedTrace = decided.trace;
      final candidates = <CandidateGenerationDebugCandidate>[];
      for (final candidate in decided.candidates) {
        candidates.add(CandidateGenerationDebugCandidate(
          candidate: candidate,
          evaluationOrder:
              decidedTrace.evaluationOrder.indexOf(candidate.productId) + 1,
          generationOrder:
              decidedTrace.generationOrder.indexOf(candidate.productId) + 1,
          rank: decidedTrace.rankingEvidence[candidate.productId]!.rank,
          rankingEvidence: decidedTrace.rankingEvidence[candidate.productId]!,
        ));
      }
      inspected.add(CandidateGenerationDebugLine(
        receiptLineId: line.id,
        originalProductText: originalText,
        trace: decidedTrace,
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
