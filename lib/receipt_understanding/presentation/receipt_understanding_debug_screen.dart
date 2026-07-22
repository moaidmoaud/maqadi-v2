import 'package:flutter/material.dart';

import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import '../application/receipt_understanding_service.dart';
import '../domain/receipt_element.dart';
import '../domain/receipt_element_evidence.dart';
import '../domain/receipt_element_type.dart';
import '../domain/receipt_understanding_failure.dart';
import '../domain/receipt_understanding_result.dart';
import 'receipt_bounding_box_overlay.dart';

class ReceiptUnderstandingDebugScreen extends StatefulWidget {
  const ReceiptUnderstandingDebugScreen({
    super.key,
    required this.service,
    required this.ocrResult,
    this.ocrReadingOrderGuaranteed = false,
  });

  final ReceiptUnderstandingService service;
  final ReceiptOcrResult ocrResult;
  final bool ocrReadingOrderGuaranteed;

  @override
  State<ReceiptUnderstandingDebugScreen> createState() =>
      _ReceiptUnderstandingDebugScreenState();
}

class _ReceiptUnderstandingDebugScreenState
    extends State<ReceiptUnderstandingDebugScreen> {
  _DebugView _view = _DebugView.classified;
  ReceiptElementType? _filter;
  ReceiptUnderstandingResult? _result;
  ReceiptUnderstandingFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _result = null;
      _failure = null;
    });
    try {
      final result = await widget.service.understand(
        widget.ocrResult,
        ocrReadingOrderGuaranteed: widget.ocrReadingOrderGuaranteed,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on ReceiptUnderstandingFailure catch (failure) {
      if (!mounted) return;
      setState(() => _failure = failure);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('receipt-understanding-debug-screen'),
        appBar: AppBar(
          title: const Text('Receipt structure debug'),
          actions: [
            PopupMenuButton<Object>(
              key: const ValueKey('receipt-element-filter'),
              tooltip: 'Filter element types',
              onSelected: (value) => setState(
                () => _filter = value is ReceiptElementType ? value : null,
              ),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: '_all',
                  child: Text('All element types'),
                ),
                for (final type in ReceiptElementType.values)
                  PopupMenuItem(value: type, child: Text(_typeLabel(type))),
              ],
              icon:
                  Icon(_filter == null ? Icons.filter_list : Icons.filter_alt),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<_DebugView>(
                segments: const [
                  ButtonSegment(
                    value: _DebugView.original,
                    label: Text('OCR blocks'),
                  ),
                  ButtonSegment(
                    value: _DebugView.classified,
                    label: Text('Elements'),
                  ),
                  ButtonSegment(
                    value: _DebugView.overlay,
                    label: Text('Overlay'),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (selection) =>
                    setState(() => _view = selection.single),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      );

  Widget _body() {
    final failure = _failure;
    if (failure != null) {
      return Center(
        key: const ValueKey('receipt-understanding-error'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(failure.message),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final result = _result;
    if (result == null) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('receipt-understanding-loading'),
        ),
      );
    }
    if (result.elements.isEmpty) {
      return const Center(
        key: ValueKey('receipt-understanding-empty'),
        child: Text('No OCR blocks are available.'),
      );
    }
    return switch (_view) {
      _DebugView.original => _originalBlocks(),
      _DebugView.classified => _classifiedElements(result),
      _DebugView.overlay => Padding(
          padding: const EdgeInsets.all(16),
          child: ReceiptBoundingBoxOverlay(elements: _visible(result.elements)),
        ),
    };
  }

  Widget _originalBlocks() => ListView.builder(
        key: const ValueKey('receipt-original-blocks'),
        padding: const EdgeInsets.all(12),
        itemCount: widget.ocrResult.blocks.length,
        itemBuilder: (context, index) {
          final block = widget.ocrResult.blocks[index];
          return Card(
            child: ListTile(
              title: Text(block.text),
              subtitle: Text(
                'Confidence: ${_confidence(block.confidence)}\n'
                'Box: ${_region(block.region)}',
              ),
            ),
          );
        },
      );

  Widget _classifiedElements(ReceiptUnderstandingResult result) {
    final elements = _visible(result.elements);
    if (elements.isEmpty) {
      return const Center(child: Text('No elements match this filter.'));
    }
    return ListView.builder(
      key: const ValueKey('receipt-classified-elements'),
      padding: const EdgeInsets.all(12),
      itemCount: elements.length,
      itemBuilder: (context, index) {
        final element = elements[index];
        return Card(
          key: ValueKey('receipt-element-${element.id}'),
          child: ListTile(
            title: Text(element.text),
            subtitle: Text(
              '${_typeLabel(element.type)} • OCR confidence: '
              '${_confidence(element.confidence)}',
            ),
            trailing: IconButton(
              key: ValueKey('receipt-element-evidence-${element.id}'),
              tooltip: 'Classification evidence',
              onPressed: () => _showEvidence(element.evidence),
              icon: const Icon(Icons.info_outline),
            ),
          ),
        );
      },
    );
  }

  List<ReceiptElement> _visible(List<ReceiptElement> elements) =>
      _filter == null
          ? elements
          : elements.where((element) => element.type == _filter).toList();

  void _showEvidence(ReceiptElementEvidence evidence) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Classification evidence',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _EvidenceRow('Rule', evidence.matchedRule),
            _EvidenceRow('Normalized text', evidence.normalizedText),
            _EvidenceRow('Position', evidence.relativePosition.name),
            _EvidenceRow(
              'Neighbours',
              evidence.neighbourReferences.isEmpty
                  ? 'None'
                  : evidence.neighbourReferences.join(', '),
            ),
            _EvidenceRow(
              'Patterns',
              evidence.matchedStructuralPatterns.isEmpty
                  ? 'None'
                  : evidence.matchedStructuralPatterns.join(', '),
            ),
            _EvidenceRow(
              'OCR confidence',
              _confidence(evidence.ocrConfidence),
            ),
            if (evidence.summary != null) Text(evidence.summary!),
          ],
        ),
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(label)),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

enum _DebugView { original, classified, overlay }

String _confidence(double? confidence) =>
    confidence == null ? 'Not available' : confidence.toStringAsFixed(2);

String _region(ReceiptOcrRegion? region) => region == null
    ? 'Not available'
    : '${region.x}, ${region.y}, ${region.width} × ${region.height}';

String _typeLabel(ReceiptElementType type) => switch (type) {
      ReceiptElementType.unknown => 'Unknown',
      ReceiptElementType.storeName => 'Store name',
      ReceiptElementType.header => 'Header',
      ReceiptElementType.productName => 'Product name',
      ReceiptElementType.price => 'Price',
      ReceiptElementType.quantity => 'Quantity',
      ReceiptElementType.discount => 'Discount',
      ReceiptElementType.tax => 'Tax',
      ReceiptElementType.total => 'Total',
      ReceiptElementType.metadata => 'Metadata',
      ReceiptElementType.footer => 'Footer',
    };
