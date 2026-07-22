import '../domain/receipt_element_type.dart';
import '../domain/receipt_relative_position.dart';
import 'structural_receipt_dictionary.dart';

class ReceiptBlockFeatures {
  const ReceiptBlockFeatures({
    required this.id,
    required this.normalizedText,
    required this.relativePosition,
    required this.previousId,
    required this.previousText,
    required this.nextId,
    required this.nextText,
    required this.isStoreNameCandidate,
  });

  final String id;
  final String normalizedText;
  final ReceiptRelativePosition relativePosition;
  final String? previousId;
  final String? previousText;
  final String? nextId;
  final String? nextText;
  final bool isStoreNameCandidate;
}

class ReceiptClassification {
  ReceiptClassification({
    required this.type,
    required this.matchedRule,
    required Iterable<String> matchedPatterns,
    required this.summary,
  }) : matchedPatterns = List.unmodifiable(matchedPatterns);

  final ReceiptElementType type;
  final String matchedRule;
  final List<String> matchedPatterns;
  final String summary;
}

class ReceiptClassificationRules {
  const ReceiptClassificationRules();

  ReceiptClassification classify(ReceiptBlockFeatures features) {
    final text = features.normalizedText;
    final neighbours = [features.previousText, features.nextText]
        .whereType<String>()
        .toList(growable: false);

    final total = _matchedTerms(text, StructuralReceiptDictionary.totalTerms);
    final neighbourTotal = _matchedNeighbourTerms(
      neighbours,
      StructuralReceiptDictionary.totalTerms,
    );
    if (total.isNotEmpty ||
        (looksMonetary(text) && neighbourTotal.isNotEmpty)) {
      return _classification(
        ReceiptElementType.total,
        'total',
        [...total, ...neighbourTotal],
      );
    }

    final tax = _matchedTerms(text, StructuralReceiptDictionary.taxTerms);
    final neighbourTax = _matchedNeighbourTerms(
      neighbours,
      StructuralReceiptDictionary.taxTerms,
    );
    if (tax.isNotEmpty ||
        (looksFinancialValue(text) && neighbourTax.isNotEmpty)) {
      return _classification(
        ReceiptElementType.tax,
        'tax',
        [...tax, ...neighbourTax],
      );
    }

    final discount =
        _matchedTerms(text, StructuralReceiptDictionary.discountTerms);
    final neighbourDiscount = _matchedNeighbourTerms(
      neighbours,
      StructuralReceiptDictionary.discountTerms,
    );
    if (discount.isNotEmpty ||
        (looksNegativeMoney(text) && neighbourDiscount.isNotEmpty)) {
      return _classification(
        ReceiptElementType.discount,
        'discount',
        [...discount, ...neighbourDiscount],
      );
    }

    final quantity =
        _matchedTerms(text, StructuralReceiptDictionary.quantityTerms);
    final neighbourQuantity = _matchedNeighbourTerms(
      neighbours,
      StructuralReceiptDictionary.quantityTerms,
    );
    if (quantity.isNotEmpty ||
        looksQuantity(text) ||
        (looksUnsignedNumber(text) && neighbourQuantity.isNotEmpty)) {
      return _classification(
        ReceiptElementType.quantity,
        'quantity',
        [...quantity, ...neighbourQuantity],
      );
    }

    if (looksMonetary(text) && !looksMetadataShape(text)) {
      return _classification(
        ReceiptElementType.price,
        'price',
        const ['monetary-value'],
      );
    }

    final metadata =
        _matchedTerms(text, StructuralReceiptDictionary.metadataTerms);
    if (metadata.isNotEmpty || looksMetadataShape(text)) {
      return _classification(
        ReceiptElementType.metadata,
        'metadata',
        metadata.isEmpty ? const ['metadata-shape'] : metadata,
      );
    }

    if (features.isStoreNameCandidate) {
      return _classification(
        ReceiptElementType.storeName,
        'store-name-prominence',
        const ['top-zone-prominence'],
      );
    }

    if (features.relativePosition == ReceiptRelativePosition.header) {
      return _classification(
        ReceiptElementType.header,
        'header-zone',
        const ['top-20-percent'],
      );
    }

    final footer = _matchedTerms(text, StructuralReceiptDictionary.footerTerms);
    if (features.relativePosition == ReceiptRelativePosition.footer ||
        footer.isNotEmpty) {
      return _classification(
        ReceiptElementType.footer,
        'footer',
        footer.isEmpty ? const ['bottom-20-percent'] : footer,
      );
    }

    if (features.relativePosition == ReceiptRelativePosition.body &&
        looksPrimarilyTextual(text) &&
        neighbours.any(looksMonetary)) {
      return _classification(
        ReceiptElementType.productName,
        'product-like-body-text',
        const ['body-text-near-price'],
      );
    }

    return _classification(
      ReceiptElementType.unknown,
      'unknown-fallback',
      const [],
    );
  }

  bool isSpecificStructuralText(String text) =>
      _matchedTerms(text, StructuralReceiptDictionary.totalTerms).isNotEmpty ||
      _matchedTerms(text, StructuralReceiptDictionary.taxTerms).isNotEmpty ||
      _matchedTerms(text, StructuralReceiptDictionary.discountTerms)
          .isNotEmpty ||
      _matchedTerms(text, StructuralReceiptDictionary.quantityTerms)
          .isNotEmpty ||
      _matchedTerms(text, StructuralReceiptDictionary.metadataTerms)
          .isNotEmpty ||
      _matchedTerms(text, StructuralReceiptDictionary.footerTerms).isNotEmpty ||
      looksFinancialValue(text) ||
      looksMetadataShape(text);

  bool looksPrimarilyTextual(String text) {
    final letters = RegExp(r'[A-Za-z\u0600-\u06ff]').allMatches(text).length;
    final digits = RegExp(r'\d').allMatches(text).length;
    return letters >= 2 && letters > digits;
  }

  bool looksMonetary(String text) {
    final currency = RegExp(
      r'(?:sar|s\.a\.r|usd|eur|ريال|ر\.?س|[$€£])',
      caseSensitive: false,
    ).hasMatch(text);
    final decimal = RegExp(r'(?<!\d)-?\d+[.,]\d{2}(?!\d)').hasMatch(text);
    return currency && RegExp(r'\d').hasMatch(text) || decimal;
  }

  bool looksFinancialValue(String text) =>
      looksMonetary(text) ||
      RegExp(r'(?<!\d)\d+(?:[.,]\d+)?\s*%(?!\w)').hasMatch(text);

  bool looksNegativeMoney(String text) =>
      RegExp(r'(^|\s)-\s*\d').hasMatch(text) && looksMonetary(text);

  bool looksQuantity(String text) => RegExp(
        r'(^|\s)\d+(?:[.,]\d+)?\s*[x×]\s*\d+(?:[.,]\d+)?($|\s)',
        caseSensitive: false,
      ).hasMatch(text);

  bool looksUnsignedNumber(String text) =>
      RegExp(r'^\s*\d+(?:[.,]\d+)?\s*$').hasMatch(text);

  bool looksMetadataShape(String text) =>
      RegExp(r'\b\d{1,4}[-/]\d{1,2}[-/]\d{1,4}\b').hasMatch(text) ||
      RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\b').hasMatch(text) ||
      RegExp(r'\b(?:ref|receipt|invoice|فاتوره|ايصال)\s*[:#-]?\s*\w+',
              caseSensitive: false)
          .hasMatch(text);

  List<String> _matchedTerms(String text, Set<String> terms) =>
      terms.where(text.contains).toList(growable: false)..sort();

  List<String> _matchedNeighbourTerms(
    List<String> neighbours,
    Set<String> terms,
  ) =>
      terms
          .where((term) => neighbours.any((text) => text.contains(term)))
          .map((term) => 'neighbour:$term')
          .toList(growable: false)
        ..sort();

  ReceiptClassification _classification(
    ReceiptElementType type,
    String rule,
    Iterable<String> patterns,
  ) =>
      ReceiptClassification(
        type: type,
        matchedRule: rule,
        matchedPatterns: patterns,
        summary: _summary(type),
      );

  String _summary(ReceiptElementType type) => switch (type) {
        ReceiptElementType.unknown =>
          'No structural rule safely classified this OCR block.',
        ReceiptElementType.storeName =>
          'Selected as the single prominent top-zone text block.',
        ReceiptElementType.header =>
          'Classified as structural text in the top twenty percent.',
        ReceiptElementType.productName =>
          'Classified as product-like body text near a monetary value.',
        ReceiptElementType.price => 'Classified as a generic monetary value.',
        ReceiptElementType.quantity =>
          'Classified from a structural quantity pattern.',
        ReceiptElementType.discount =>
          'Classified from structural discount evidence.',
        ReceiptElementType.tax => 'Classified from structural tax evidence.',
        ReceiptElementType.total =>
          'Classified from structural total evidence.',
        ReceiptElementType.metadata =>
          'Classified as structural receipt metadata.',
        ReceiptElementType.footer => 'Classified as structural footer content.',
      };
}
