import 'product_match_reason.dart';

class ProductMatchCandidate {
  ProductMatchCandidate({
    required this.productId,
    required this.displayName,
    required this.matchingScore,
    required this.confidence,
    required Map<String, String> evidence,
    required this.matchReason,
  })  : assert(matchingScore >= 0 && matchingScore <= 1),
        assert(confidence >= 0 && confidence <= 1),
        evidence = Map.unmodifiable(evidence);

  factory ProductMatchCandidate.fromJson(Map<String, Object?> json) =>
      ProductMatchCandidate(
        productId: json['productId']! as String,
        displayName: json['displayName']! as String,
        matchingScore: (json['matchingScore']! as num).toDouble(),
        confidence: (json['confidence']! as num).toDouble(),
        evidence: (json['evidence']! as Map<Object?, Object?>).map(
          (key, value) => MapEntry(key! as String, value! as String),
        ),
        matchReason: ProductMatchReason.values.byName(
          json['matchReason']! as String,
        ),
      );

  final String productId;
  final String displayName;
  final double matchingScore;
  final double confidence;
  final Map<String, String> evidence;
  final ProductMatchReason matchReason;

  Map<String, Object> toJson() => {
        'productId': productId,
        'displayName': displayName,
        'matchingScore': matchingScore,
        'confidence': confidence,
        'evidence': evidence,
        'matchReason': matchReason.name,
      };
}
