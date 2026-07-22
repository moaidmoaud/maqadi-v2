import '../../receipt_line_builder/domain/receipt_line_completeness.dart';
import '../../receipt_understanding/domain/receipt_element_type.dart';

class ExpectedReceiptElement {
  const ExpectedReceiptElement({required this.fixtureKey, required this.type});

  final String fixtureKey;
  final ReceiptElementType type;

  factory ExpectedReceiptElement.fromJson(Map<String, Object?> json) =>
      ExpectedReceiptElement(
        fixtureKey: json['fixtureKey']! as String,
        type: ReceiptElementType.values.byName(json['type']! as String),
      );
}

class ExpectedReceiptLine {
  const ExpectedReceiptLine({
    required this.fixtureKey,
    required this.productKey,
    required this.priceKey,
    required this.quantityKey,
    required this.discountKey,
    required this.taxKey,
    required this.lineTotalKey,
    required this.completeness,
  });

  final String fixtureKey;
  final String? productKey;
  final String? priceKey;
  final String? quantityKey;
  final String? discountKey;
  final String? taxKey;
  final String? lineTotalKey;
  final ReceiptLineCompleteness completeness;

  factory ExpectedReceiptLine.fromJson(Map<String, Object?> json) =>
      ExpectedReceiptLine(
        fixtureKey: json['fixtureKey']! as String,
        productKey: json['productKey'] as String?,
        priceKey: json['priceKey'] as String?,
        quantityKey: json['quantityKey'] as String?,
        discountKey: json['discountKey'] as String?,
        taxKey: json['taxKey'] as String?,
        lineTotalKey: json['lineTotalKey'] as String?,
        completeness: ReceiptLineCompleteness.values
            .byName(json['completeness']! as String),
      );

  Map<String, String?> get roles => Map.unmodifiable({
        'product': productKey,
        'quantity': quantityKey,
        'price': priceKey,
        'lineTotal': lineTotalKey,
        'discount': discountKey,
        'tax': taxKey,
      });

  Set<String> get referencedKeys => roles.values.whereType<String>().toSet();

  String get identityKey =>
      productKey ?? roles.values.whereType<String>().first;
}

class ReceiptBenchmarkGroundTruth {
  ReceiptBenchmarkGroundTruth({
    required this.manuallyVerified,
    required this.scope,
    required this.ocrTextVerified,
    required Iterable<ExpectedReceiptElement> expectedElements,
    required Iterable<ExpectedReceiptLine> expectedLines,
    required Iterable<String> expectedUnassignedKeys,
  })  : expectedElements = List.unmodifiable(expectedElements),
        expectedLines = List.unmodifiable(expectedLines),
        expectedUnassignedKeys = List.unmodifiable(expectedUnassignedKeys);

  final bool manuallyVerified;
  final String scope;
  final bool ocrTextVerified;
  final List<ExpectedReceiptElement> expectedElements;
  final List<ExpectedReceiptLine> expectedLines;
  final List<String> expectedUnassignedKeys;

  factory ReceiptBenchmarkGroundTruth.fromJson(Map<String, Object?> json) =>
      ReceiptBenchmarkGroundTruth(
        manuallyVerified: json['manuallyVerified']! as bool,
        scope: json['scope']! as String,
        ocrTextVerified: json['ocrTextVerified']! as bool,
        expectedElements: (json['expectedElements']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(ExpectedReceiptElement.fromJson),
        expectedLines: (json['expectedLines']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(ExpectedReceiptLine.fromJson),
        expectedUnassignedKeys:
            (json['expectedUnassignedKeys']! as List<Object?>).cast<String>(),
      );
}
