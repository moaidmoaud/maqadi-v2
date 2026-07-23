import '../../receipt_line_builder/domain/receipt_line.dart';
import '../domain/candidate_generation_diagnostics.dart';
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
    final normalization = _normalizer.normalizeWithTrace(
      await _textResolver.resolve(line) ?? '',
    );
    final query = normalization.normalizedText;
    final products = query.isEmpty
        ? const <ProductCatalogEntry>[]
        : await _catalog.readProducts();
    final queryTokens =
        query.split(' ').where((value) => value.isNotEmpty).toSet();
    final candidates = <ProductMatchCandidate>[];
    final generatedIds = <String>{};
    final evaluationOrder = <String>[];
    final evidence = <String, ProductMatchEvidence>{};
    final seenProductIds = <String>{};
    var validCatalogEntryCount = 0;
    var invalidCatalogEntryCount = 0;
    var duplicateProductIdCount = 0;
    var evaluatedEntryCount = 0;
    var rejectedNoTextCount = 0;
    var rejectedNoTokenOverlapCount = 0;
    final catalogPreview = <CandidateCatalogPreviewEntry>[];

    for (final product in products) {
      evaluationOrder.add(product.id);
      if (product.id.trim().isEmpty || product.displayName.trim().isEmpty) {
        invalidCatalogEntryCount++;
        continue;
      }
      validCatalogEntryCount++;
      if (!seenProductIds.add(product.id)) duplicateProductIdCount++;
      final normalizedCatalogName = _normalizer.normalize(product.displayName);
      if (normalizedCatalogName.isNotEmpty &&
          catalogPreview.length < _catalogPreviewLimit) {
        catalogPreview.add(CandidateCatalogPreviewEntry(
          productId: product.id,
          normalizedName: normalizedCatalogName,
        ));
      }
      if (generatedIds.contains(product.id)) continue;
      evaluatedEntryCount++;
      final discovery = _discover(product, query, queryTokens);
      switch (discovery.outcome) {
        case _CandidateDiscoveryOutcome.noText:
          rejectedNoTextCount++;
          continue;
        case _CandidateDiscoveryOutcome.noTokenOverlap:
          rejectedNoTokenOverlapCount++;
          continue;
        case _CandidateDiscoveryOutcome.accepted:
          break;
      }
      generatedIds.add(product.id);
      final accepted = discovery.discovery!;
      evidence[product.id] = accepted.evidence;
      candidates.add(ProductMatchCandidate(
        productId: product.id,
        displayName: product.displayName,
        matchingScore: 0,
        confidence: 0,
        evidence: accepted.evidence,
        matchReason: accepted.reason,
      ));
    }

    final result = List<ProductMatchCandidate>.unmodifiable(candidates);
    final diagnostics = CandidateGenerationDiagnostics(
      reason: _diagnosticReason(
        query: query,
        catalogEntryCount: products.length,
        validCatalogEntryCount: validCatalogEntryCount,
        acceptedCount: result.length,
      ),
      catalogEntryCount: products.length,
      validCatalogEntryCount: validCatalogEntryCount,
      invalidCatalogEntryCount: invalidCatalogEntryCount,
      duplicateProductIdCount: duplicateProductIdCount,
      evaluatedEntryCount: evaluatedEntryCount,
      rejectedNoTextCount: rejectedNoTextCount,
      rejectedNoTokenOverlapCount: rejectedNoTokenOverlapCount,
      acceptedCount: result.length,
      catalogPreview: catalogPreview,
    );
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
      originalQueryText: normalization.originalText,
      preCorrectionNormalizedQuery: normalization.preCorrectionNormalizedText,
      normalizedQuery: query,
      appliedNormalizationOperations: normalization.appliedOperations,
      candidateGenerationDiagnostics: diagnostics,
      generatedCandidateCount: result.length,
      generatedCandidateIds: result.map((value) => value.productId),
      generationOrder: result.map((value) => value.productId),
      discoveryEvidence: evidence,
    ));
    return result;
  }

  CandidateGenerationDiagnosticReason _diagnosticReason({
    required String query,
    required int catalogEntryCount,
    required int validCatalogEntryCount,
    required int acceptedCount,
  }) {
    if (query.isEmpty) {
      return CandidateGenerationDiagnosticReason.noProductText;
    }
    if (catalogEntryCount == 0) {
      return CandidateGenerationDiagnosticReason.emptyCatalog;
    }
    if (validCatalogEntryCount == 0) {
      return CandidateGenerationDiagnosticReason.noValidCatalogEntries;
    }
    if (acceptedCount == 0) {
      return CandidateGenerationDiagnosticReason.noCandidateMatch;
    }
    return CandidateGenerationDiagnosticReason.candidatesGenerated;
  }

  _CandidateDiscoveryResult _discover(
    ProductCatalogEntry product,
    String query,
    Set<String> queryTokens,
  ) {
    _CandidateDiscovery? tokenDiscovery;
    var hasSearchableText = false;
    final texts = <(String, ProductMatchDiscoverySource)>[
      (product.displayName, ProductMatchDiscoverySource.catalogName),
      for (final alias in product.aliases)
        (alias, ProductMatchDiscoverySource.catalogAlias),
    ];
    for (final (text, source) in texts) {
      final normalized = _normalizer.normalize(text);
      if (normalized.isEmpty) continue;
      hasSearchableText = true;
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
      if (exact) {
        return _CandidateDiscoveryResult.accepted(current);
      }
      if (matchedTokens.isNotEmpty && tokenDiscovery == null) {
        tokenDiscovery = current;
      }
    }
    if (tokenDiscovery != null) {
      return _CandidateDiscoveryResult.accepted(tokenDiscovery);
    }
    return hasSearchableText
        ? const _CandidateDiscoveryResult.noTokenOverlap()
        : const _CandidateDiscoveryResult.noText();
  }

  static const int _catalogPreviewLimit = 5;
}

class _CandidateDiscovery {
  const _CandidateDiscovery({required this.reason, required this.evidence});

  final ProductMatchReason reason;
  final ProductMatchEvidence evidence;
}

enum _CandidateDiscoveryOutcome { accepted, noText, noTokenOverlap }

class _CandidateDiscoveryResult {
  const _CandidateDiscoveryResult.accepted(this.discovery)
      : outcome = _CandidateDiscoveryOutcome.accepted;

  const _CandidateDiscoveryResult.noText()
      : outcome = _CandidateDiscoveryOutcome.noText,
        discovery = null;

  const _CandidateDiscoveryResult.noTokenOverlap()
      : outcome = _CandidateDiscoveryOutcome.noTokenOverlap,
        discovery = null;

  final _CandidateDiscoveryOutcome outcome;
  final _CandidateDiscovery? discovery;
}
