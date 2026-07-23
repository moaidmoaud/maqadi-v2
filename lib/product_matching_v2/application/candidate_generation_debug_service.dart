import '../../receipt_line_builder/domain/receipt_line.dart';
import '../domain/product_match_candidate.dart';
import '../domain/product_match_trace.dart';
import 'candidate_generation_service.dart';

enum CandidateGenerationEmptyReason {
  noProductText,
  emptyCatalog,
  noValidCandidates,
}

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
    required this.emptyReason,
  }) : candidates = List.unmodifiable(candidates);

  final String receiptLineId;
  final String? originalProductText;
  final ProductMatchTrace trace;
  final List<CandidateGenerationDebugCandidate> candidates;
  final CandidateGenerationEmptyReason? emptyReason;
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
    final results = <CandidateGenerationDebugLine>[];
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
      results.add(CandidateGenerationDebugLine(
        receiptLineId: line.id,
        originalProductText: originalText,
        trace: generatedTrace,
        candidates: candidates,
        emptyReason: _emptyReason(originalText, generatedTrace, generated),
      ));
    }
    return List.unmodifiable(results);
  }

  CandidateGenerationEmptyReason? _emptyReason(
    String? originalText,
    ProductMatchTrace trace,
    List<ProductMatchCandidate> candidates,
  ) {
    if (candidates.isNotEmpty) return null;
    if (originalText == null || trace.normalizedQuery?.isEmpty != false) {
      return CandidateGenerationEmptyReason.noProductText;
    }
    if (trace.evaluationOrder.isEmpty) {
      return CandidateGenerationEmptyReason.emptyCatalog;
    }
    return CandidateGenerationEmptyReason.noValidCandidates;
  }
}

class _ResolvedTextResolver implements ReceiptLineProductTextResolver {
  const _ResolvedTextResolver(this.value);

  final String? value;

  @override
  Future<String?> resolve(ReceiptLine line) async => value;
}
