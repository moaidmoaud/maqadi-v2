import '../../receipt_line_builder/domain/receipt_line.dart';
import '../domain/product_catalog_entry.dart';
import '../domain/product_match_candidate.dart';
import '../domain/product_match_evidence.dart';
import '../domain/product_match_reason.dart';
import '../domain/product_match_trace.dart';
import '../engine/candidate_text_normalizer.dart';

abstract interface class ProductCandidateCatalog {
  Future<List<ProductCatalogEntry>> readProducts();
}

abstract interface class ReceiptLineProductTextResolver {
  Future<String?> resolve(ReceiptLine line);
}

typedef ProductMatchTraceCallback = void Function(ProductMatchTrace trace);

class CandidateGenerationService {
  const CandidateGenerationService({
    required ProductCandidateCatalog catalog,
    required ReceiptLineProductTextResolver textResolver,
    CandidateTextNormalizer normalizer = const CandidateTextNormalizer(),
    ProductMatchTraceCallback? onTrace,
  })  : _catalog = catalog,
        _textResolver = textResolver,
        _normalizer = normalizer,
        _onTrace = onTrace;

  final ProductCandidateCatalog _catalog;
  final ReceiptLineProductTextResolver _textResolver;
  final CandidateTextNormalizer _normalizer;
  final ProductMatchTraceCallback? _onTrace;

  Future<List<ProductMatchCandidate>> generate(ReceiptLine line) async {
    final query =
        _normalizer.normalize(await _textResolver.resolve(line) ?? '');
    final products = query.isEmpty
        ? const <ProductCatalogEntry>[]
        : await _catalog.readProducts();
    final queryTokens =
        query.split(' ').where((value) => value.isNotEmpty).toSet();
    final candidates = <ProductMatchCandidate>[];
    final generatedIds = <String>{};
    final evaluationOrder = <String>[];
    final evidence = <String, ProductMatchEvidence>{};

    for (final product in products) {
      evaluationOrder.add(product.id);
      if (product.id.trim().isEmpty || product.displayName.trim().isEmpty) {
        continue;
      }
      if (generatedIds.contains(product.id)) continue;
      final discovery = _discover(product, query, queryTokens);
      if (discovery == null) continue;
      generatedIds.add(product.id);
      evidence[product.id] = discovery.evidence;
      candidates.add(ProductMatchCandidate(
        productId: product.id,
        displayName: product.displayName,
        matchingScore: 0,
        confidence: 0,
        evidence: discovery.evidence,
        matchReason: discovery.reason,
      ));
    }

    final result = List<ProductMatchCandidate>.unmodifiable(candidates);
    _onTrace?.call(ProductMatchTrace(
      evaluationOrder: evaluationOrder,
      candidateRanking: const [],
      winningCandidate: null,
      rejectedCandidates: const [],
      evidence: const {
        'stage': 'candidateGeneration',
        'ranking': 'notPerformed',
        'selection': 'notPerformed',
      },
      finalDecision: ProductMatchReason.notEvaluated,
      normalizedQuery: query,
      generatedCandidateCount: result.length,
      generatedCandidateIds: result.map((value) => value.productId),
      generationOrder: result.map((value) => value.productId),
      discoveryEvidence: evidence,
    ));
    return result;
  }

  _CandidateDiscovery? _discover(
    ProductCatalogEntry product,
    String query,
    Set<String> queryTokens,
  ) {
    _CandidateDiscovery? tokenDiscovery;
    final texts = <(String, ProductMatchDiscoverySource)>[
      (product.displayName, ProductMatchDiscoverySource.catalogName),
      for (final alias in product.aliases)
        (alias, ProductMatchDiscoverySource.catalogAlias),
    ];
    for (final (text, source) in texts) {
      final normalized = _normalizer.normalize(text);
      if (normalized.isEmpty) continue;
      final matchedTokens = normalized
          .split(' ')
          .where(queryTokens.contains)
          .toSet()
          .toList(growable: false);
      final exact = normalized == query;
      final current = _CandidateDiscovery(
        reason: exact
            ? ProductMatchReason.exactMatch
            : ProductMatchReason.normalizedMatch,
        evidence: ProductMatchEvidence(
          normalizedQuery: query,
          normalizedCatalogText: normalized,
          matchedTokens: matchedTokens,
          exactNormalizedMatch: exact,
          discoverySource: source,
        ),
      );
      if (exact) return current;
      if (matchedTokens.isNotEmpty && tokenDiscovery == null) {
        tokenDiscovery = current;
      }
    }
    return tokenDiscovery;
  }
}

class _CandidateDiscovery {
  const _CandidateDiscovery({required this.reason, required this.evidence});

  final ProductMatchReason reason;
  final ProductMatchEvidence evidence;
}
