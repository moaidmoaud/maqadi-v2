import 'package:flutter/material.dart';

import '../../receipt_understanding/domain/receipt_element.dart';

class ReceiptLineElementHighlight extends StatelessWidget {
  const ReceiptLineElementHighlight({
    super.key,
    required this.elements,
    required this.highlightedElementIds,
  });

  final List<ReceiptElement> elements;
  final Set<String> highlightedElementIds;

  @override
  Widget build(BuildContext context) => Wrap(
        key: const ValueKey('receipt-line-element-highlights'),
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final element in elements)
            Chip(
              key: ValueKey('receipt-line-highlight-${element.id}'),
              avatar: Icon(
                highlightedElementIds.contains(element.id)
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
              ),
              backgroundColor: highlightedElementIds.contains(element.id)
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
              label: Text(element.text),
            ),
        ],
      );
}
