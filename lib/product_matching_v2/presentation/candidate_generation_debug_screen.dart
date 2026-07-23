import 'package:flutter/material.dart';

import '../../receipt_line_builder/domain/receipt_line.dart';
import '../application/candidate_generation_debug_service.dart';

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
  Widget build(BuildContext context) => Card(
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
                label: 'Normalized query',
                value: result.trace.normalizedQuery?.isNotEmpty == true
                    ? result.trace.normalizedQuery!
                    : 'None',
              ),
              _Field(
                label: 'Candidate count',
                value: '${result.trace.generatedCandidateCount}',
              ),
              const _Field(label: 'Ranking', value: 'Not executed'),
              const _Field(label: 'Selection', value: 'Not executed'),
              if (result.emptyReason != null)
                Padding(
                  key: ValueKey(
                    'candidate-generation-empty-${result.receiptLineId}',
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _emptyReasonLabel(result.emptyReason!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              for (final value in result.candidates)
                _CandidateCard(value: value),
            ],
          ),
        ),
      );
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.value});

  final CandidateGenerationDebugCandidate value;

  @override
  Widget build(BuildContext context) {
    final candidate = value.candidate;
    final evidence = candidate.evidence;
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
            _Field(label: 'Candidate type', value: candidate.matchReason.name),
            _Field(
              label: 'Evaluation / generation order',
              value: '${value.evaluationOrder} / ${value.generationOrder}',
            ),
            _Field(label: 'Score', value: '${candidate.matchingScore}'),
            _Field(label: 'Confidence', value: '${candidate.confidence}'),
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

String _emptyReasonLabel(CandidateGenerationEmptyReason reason) =>
    switch (reason) {
      CandidateGenerationEmptyReason.noProductText => 'No product text',
      CandidateGenerationEmptyReason.emptyCatalog => 'Empty catalog',
      CandidateGenerationEmptyReason.noValidCandidates => 'No valid candidates',
    };
