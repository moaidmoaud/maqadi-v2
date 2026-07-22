import 'product_match_candidate.dart';
import 'product_match_reason.dart';
import 'product_match_trace.dart';

enum ProductMatchStatus { pending, matched, ambiguous, lowConfidence, noMatch }

class ProductMatchResult {
  ProductMatchResult({
    required this.receiptLineId,
    required this.matchedProduct,
    required Iterable<ProductMatchCandidate> candidates,
    required this.finalConfidence,
    required this.status,
    required this.decisionReason,
    required this.trace,
  })  : assert(finalConfidence == null ||
            (finalConfidence >= 0 && finalConfidence <= 1)),
        candidates = List.unmodifiable(candidates);

  factory ProductMatchResult.fromJson(Map<String, Object?> json) =>
      ProductMatchResult(
        receiptLineId: json['receiptLineId']! as String,
        matchedProduct: json['matchedProduct'] == null
            ? null
            : ProductMatchCandidate.fromJson(
                json['matchedProduct']! as Map<String, Object?>,
              ),
        candidates: (json['candidates']! as List<Object?>).map(
          (value) => ProductMatchCandidate.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
        finalConfidence: (json['finalConfidence'] as num?)?.toDouble(),
        status: ProductMatchStatus.values.byName(json['status']! as String),
        decisionReason: ProductMatchReason.values.byName(
          json['decisionReason']! as String,
        ),
        trace: ProductMatchTrace.fromJson(
          json['trace']! as Map<String, Object?>,
        ),
      );

  final String receiptLineId;
  final ProductMatchCandidate? matchedProduct;
  final List<ProductMatchCandidate> candidates;
  final double? finalConfidence;
  final ProductMatchStatus status;
  final ProductMatchReason decisionReason;
  final ProductMatchTrace trace;

  Map<String, Object?> toJson() => {
        'receiptLineId': receiptLineId,
        'matchedProduct': matchedProduct?.toJson(),
        'candidates': [for (final value in candidates) value.toJson()],
        'finalConfidence': finalConfidence,
        'status': status.name,
        'decisionReason': decisionReason.name,
        'trace': trace.toJson(),
      };
}
