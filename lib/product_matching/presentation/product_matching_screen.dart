import 'package:flutter/material.dart';

import '../application/product_matching_service.dart';
import '../domain/matching_failure.dart';
import '../domain/product_match_models.dart';

enum ProductMatchingViewStatus { loading, candidates, noMatches, error }

class ProductMatchingScreen extends StatefulWidget {
  const ProductMatchingScreen({
    super.key,
    required this.service,
    required this.request,
    this.onSelected,
  });

  final ProductMatchingService service;
  final ProductMatchRequest request;
  final ValueChanged<MatchedProduct>? onSelected;

  @override
  State<ProductMatchingScreen> createState() => _ProductMatchingScreenState();
}

class _ProductMatchingScreenState extends State<ProductMatchingScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _skippedLines = <String>{};
  ProductMatchingViewStatus _status = ProductMatchingViewStatus.loading;
  ProductMatchResult? _result;
  String? _errorMessage;
  String? _selectedProductId;

  ProductMatchRequest get _activeRequest => widget.request.copyWith(
        excludedSourceTexts: _skippedLines,
      );

  @override
  void initState() {
    super.initState();
    _match();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _match() => _run(() => widget.service.match(_activeRequest));

  Future<void> _search() => _run(
        () => widget.service.searchManually(
          _activeRequest,
          _searchController.text,
        ),
      );

  Future<void> _skipLine(String line) async {
    setState(() => _skippedLines.add(line));
    await _match();
  }

  Future<void> _run(Future<ProductMatchResult> Function() operation) async {
    setState(() {
      _status = ProductMatchingViewStatus.loading;
      _errorMessage = null;
    });
    try {
      final result = await operation();
      if (!mounted) return;
      setState(() {
        _result = result;
        _status = ProductMatchingViewStatus.candidates;
      });
    } on NoCandidatesFound catch (failure) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _errorMessage = failure.message;
        _status = ProductMatchingViewStatus.noMatches;
      });
    } on MatchingFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _errorMessage = failure.message;
        _status = ProductMatchingViewStatus.error;
      });
    }
  }

  void _select(MatchedProduct match) {
    setState(() => _selectedProductId = match.product.id);
    widget.onSelected?.call(match);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('product-matching-screen'),
        appBar: AppBar(title: const Text('مطابقة المنتجات')),
        body: SafeArea(
          child: Column(
            children: [
              _ManualSearchBar(
                controller: _searchController,
                onSearch: _search,
              ),
              _SourceLineList(
                lines: widget.service.sourceLines(widget.request),
                skippedLines: _skippedLines,
                onSkip: _skipLine,
              ),
              Expanded(child: _buildState()),
            ],
          ),
        ),
      );

  Widget _buildState() => switch (_status) {
        ProductMatchingViewStatus.loading => const _LoadingView(),
        ProductMatchingViewStatus.candidates => ListView.builder(
            key: const ValueKey('product-match-candidates'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _result!.matches.length,
            itemBuilder: (context, index) {
              final match = _result!.matches[index];
              return _MatchCard(
                match: match,
                selected: match.product.id == _selectedProductId,
                onSelect: () => _select(match),
              );
            },
          ),
        ProductMatchingViewStatus.noMatches => _MessageView(
            key: const ValueKey('product-match-empty'),
            icon: Icons.search_off,
            message: _errorMessage!,
            actionLabel: 'إعادة المطابقة',
            onAction: _match,
          ),
        ProductMatchingViewStatus.error => _MessageView(
            key: const ValueKey('product-match-error'),
            icon: Icons.error_outline,
            message: _errorMessage!,
            actionLabel: 'إعادة المحاولة',
            onAction: _match,
          ),
      };
}

class _ManualSearchBar extends StatelessWidget {
  const _ManualSearchBar({required this.controller, required this.onSearch});

  final TextEditingController controller;
  final Future<void> Function() onSearch;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('product-match-search'),
                controller: controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearch(),
                decoration: const InputDecoration(
                  labelText: 'بحث يدوي عن منتج',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey('product-match-search-button'),
              tooltip: 'بحث',
              onPressed: onSearch,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
      );
}

class _SourceLineList extends StatelessWidget {
  const _SourceLineList({
    required this.lines,
    required this.skippedLines,
    required this.onSkip,
  });

  final List<String> lines;
  final Set<String> skippedLines;
  final Future<void> Function(String line) onSkip;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 54,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: lines.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final line = lines[index];
          final skipped = skippedLines.contains(line);
          return InputChip(
            key: ValueKey('product-match-line-$index'),
            label: Text(line),
            avatar: Icon(skipped ? Icons.block : Icons.receipt_long, size: 18),
            isEnabled: !skipped,
            deleteIcon: const Icon(Icons.skip_next, size: 18),
            deleteButtonTooltipMessage: 'تخطي السطر',
            onDeleted: skipped ? null : () => onSkip(line),
          );
        },
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.selected,
    required this.onSelect,
  });

  final MatchedProduct match;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final explanation = match.explanation;
    final percent = (match.confidence.value * 100).round();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.product.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text('$percent٪')),
              ],
            ),
            Text(match.product.category),
            const SizedBox(height: 8),
            Text('النص المطابق: ${match.matchedText}'),
            Text('الاستراتيجية: ${_strategyLabel(match.matchedStrategy)}'),
            if (explanation.summary != null) Text(explanation.summary!),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('تفاصيل المطابقة'),
              children: [
                ListTile(
                  dense: true,
                  title: const Text('نص OCR الموحد'),
                  subtitle: Text(explanation.normalizedOcrText),
                ),
                ListTile(
                  dense: true,
                  title: const Text('اسم المنتج الموحد'),
                  subtitle: Text(explanation.normalizedProductText),
                ),
                if (explanation.matchedAlias != null)
                  ListTile(
                    dense: true,
                    title: const Text('الاسم البديل المطابق'),
                    subtitle: Text(explanation.matchedAlias!),
                  ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                key: ValueKey('select-product-${match.product.id}'),
                onPressed: onSelect,
                icon: Icon(selected ? Icons.check : Icons.touch_app),
                label: Text(selected ? 'تم الاختيار' : 'اختيار المرشح'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _strategyLabel(MatchingStrategyType type) => switch (type) {
        MatchingStrategyType.exact => 'تطابق تام',
        MatchingStrategyType.normalized => 'تطابق بعد التوحيد',
        MatchingStrategyType.alias => 'اسم بديل',
        MatchingStrategyType.fuzzy => 'تطابق تقريبي',
      };
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جارٍ مطابقة المنتجات...'),
          ],
        ),
      );
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('product-match-retry'),
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
}
