import 'package:flutter/material.dart';

import '../../receipt_line_builder/domain/receipt_line.dart';
import '../application/candidate_generation_debug_service.dart';
import '../domain/candidate_generation_diagnostics.dart';
import '../domain/product_match_evidence.dart';

class CandidateGenerationDebugScreen extends StatefulWidget {
  const CandidateGenerationDebugScreen({
    super.key,
    required this.service,
    required this.lines,
  });

  final CandidateGenerationDebugService service;
  final List<ReceiptLine> lines;

  @override
  State<CandidateGenerationDebugScreen> createState() =>
      _CandidateGenerationDebugScreenState();
}

class _CandidateGenerationDebugScreenState
    extends State<CandidateGenerationDebugScreen> {
  List<CandidateGenerationDebugLine>? _results;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _results = null;
      _error = null;
    });
    try {
      final results = await widget.service.inspect(widget.lines);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('candidate-generation-debug-screen'),
        appBar: AppBar(title: const Text('Candidate Generation v2')),
        body: _body(),
      );

  Widget _body() {
    final error = _error;
    if (error != null) {
      return Center(
        key: const ValueKey('candidate-generation-debug-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Candidate generation failed: $error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final results = _results;
    if (results == null) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('candidate-generation-debug-loading'),
        ),
      );
    }
    if (results.isEmpty) {
      return const Center(
        key: ValueKey('candidate-generation-debug-empty'),
        child: Text('No receipt lines are available.'),
      );
    }
    return ListView.builder(
      key: const ValueKey('candidate-generation-debug-results'),
      padding: const EdgeInsets.all(12),
      itemCount: results.length,
      itemBuilder: (context, index) => _LineCard(result: results[index]),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.result});

  final CandidateGenerationDebugLine result;

  @override
  Widget build(BuildContext context) {
    final diagnostics = result.trace.candidateGenerationDiagnostics!;
    return Card(
      key: ValueKey('candidate-generation-line-${result.receiptLineId}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Receipt Line: ${result.receiptLineId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _Field(
              label: 'Original product text',
              value: result.originalProductText?.trim().isNotEmpty == true
                  ? result.originalProductText!
                  : 'No product text',
            ),
            _Field(
              label: 'Pre-correction normalized text',
              value:
                  result.trace.preCorrectionNormalizedQuery?.isNotEmpty == true
                      ? result.trace.preCorrectionNormalizedQuery!
                      : 'None',
            ),
            _Field(
              label: 'Final normalized query',
              value: result.trace.normalizedQuery?.isNotEmpty == true
                  ? result.trace.normalizedQuery!
                  : 'None',
            ),
            _Field(
              label: 'Applied normalization operations',
              value: result.trace.appliedNormalizationOperations.isEmpty
                  ? 'None'
                  : result.trace.appliedNormalizationOperations
                      .map((value) => value.name)
                      .join(', '),
            ),
            _Field(
              label: 'Candidate count',
              value: '${result.trace.generatedCandidateCount}',
            ),
            _Field(
              label: 'Catalog entry count',
              value: '${diagnostics.catalogEntryCount}',
            ),
            _Field(
              label: 'Valid catalog entry count',
              value: '${diagnostics.validCatalogEntryCount}',
            ),
            _Field(
              label: 'Invalid catalog entry count',
              value: '${diagnostics.invalidCatalogEntryCount}',
            ),
            _Field(
              label: 'Duplicate product ID count',
              value: '${diagnostics.duplicateProductIdCount}',
            ),
            _Field(
              label: 'Entries evaluated',
              value: '${diagnostics.evaluatedEntryCount}',
            ),
            _Field(
              label: 'Rejected for no text',
              value: '${diagnostics.rejectedNoTextCount}',
            ),
            _Field(
              label: 'Rejected for no token overlap',
              value: '${diagnostics.rejectedNoTokenOverlapCount}',
            ),
            _Field(
              label: 'Accepted',
              value: '${diagnostics.acceptedCount}',
            ),
            _Field(
              label: 'Normalized catalog preview',
              value: diagnostics.catalogPreview.isEmpty
                  ? 'None'
                  : diagnostics.catalogPreview
                      .map(
                        (value) =>
                            '${value.productId}: ${value.normalizedName}',
                      )
                      .join(' | '),
            ),
            const _Field(label: 'Ranking', value: 'Executed'),
            const _Field(label: 'Selection', value: 'Not executed'),
            if (result.hasDuplicateNormalizedQuery) ...[
              _Field(
                label: 'Duplicate normalized query',
                value: result.trace.normalizedQuery!,
              ),
              _Field(
                label: 'Related Receipt Line IDs',
                value: result.duplicateNormalizedQueryLineIds.join(', '),
              ),
            ],
            if (diagnostics.reason !=
                CandidateGenerationDiagnosticReason.candidatesGenerated)
              Padding(
                key: ValueKey(
                  'candidate-generation-empty-${result.receiptLineId}',
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  _diagnosticReasonLabel(diagnostics.reason),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            for (final value in result.candidates) _CandidateCard(value: value),
          ],
        ),
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.value});

  final CandidateGenerationDebugCandidate value;

  @override
  Widget build(BuildContext context) {
    final candidate = value.candidate;
    final evidence = candidate.evidence;
    final rankingEvidence = value.rankingEvidence;
    return Card.outlined(
      key: ValueKey('generated-candidate-${candidate.productId}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${value.generationOrder}. ${candidate.displayName}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            _Field(label: 'Product ID', value: candidate.productId),
            _Field(label: 'Rank', value: '${value.rank}'),
            _Field(label: 'Candidate type', value: candidate.matchReason.name),
            _Field(
              label: 'Evaluation / generation order',
              value: '${value.evaluationOrder} / ${value.generationOrder}',
            ),
            _Field(label: 'Score', value: '${candidate.matchingScore}'),
            _Field(label: 'Confidence', value: '${candidate.confidence}'),
            _Field(
              label: 'Ranking Evidence',
              value: rankingEvidence.factors
                  .map(
                    (factor) => '${factor.type.name}: value=${factor.value}, '
                        'weight=${factor.weight}, '
                        'contribution=${factor.contribution}',
                  )
                  .join(' | '),
            ),
            _Field(
              label: 'Normalized text matched',
              value: evidence.normalizedCatalogText,
            ),
            _Field(
              label: 'Exact normalized match',
              value: '${evidence.exactNormalizedMatch}',
            ),
            _Field(
              label: 'Matched tokens',
              value: evidence.matchedTokens.join(', '),
            ),
            _Field(
              label: 'Catalog lookup',
              value: evidence.discoverySource.name,
            ),
            _Field(
              label: 'Matched Through',
              value: evidence.discoverySource ==
                      ProductMatchDiscoverySource.catalogAlias
                  ? 'Alias'
                  : 'Canonical Name',
            ),
            _Field(
              label: 'Matched Alias',
              value: evidence.matchedAlias ?? 'None',
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text('$label: $value'),
      );
}

String _diagnosticReasonLabel(CandidateGenerationDiagnosticReason reason) =>
    switch (reason) {
      CandidateGenerationDiagnosticReason.candidatesGenerated =>
        'Candidates generated',
      CandidateGenerationDiagnosticReason.noProductText => 'No product text',
      CandidateGenerationDiagnosticReason.emptyCatalog => 'Empty catalog',
      CandidateGenerationDiagnosticReason.noValidCatalogEntries =>
        'No valid catalog entries',
      CandidateGenerationDiagnosticReason.noCandidateMatch =>
        'No candidate match',
    };
