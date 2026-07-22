import 'product_match_evidence.dart';
import 'product_match_reason.dart';

class ProductMatchCandidate {
  ProductMatchCandidate({
    required this.productId,
    required this.displayName,
    required this.matchingScore,
    required this.confidence,
    required this.evidence,
    required this.matchReason,
  })  : assert(matchingScore >= 0 && matchingScore <= 1),
        assert(confidence >= 0 && confidence <= 1);

  factory ProductMatchCandidate.fromJson(Map<String, Object?> json) =>
      ProductMatchCandidate(
        productId: json['productId']! as String,
        displayName: json['displayName']! as String,
        matchingScore: (json['matchingScore']! as num).toDouble(),
        confidence: (json['confidence']! as num).toDouble(),
        evidence: ProductMatchEvidence.fromJson(
          json['evidence']! as Map<String, Object?>,
        ),
        matchReason: ProductMatchReason.values.byName(
          json['matchReason']! as String,
        ),
      );

  final String productId;
  final String displayName;
  final double matchingScore;
  final double confidence;
  final ProductMatchEvidence evidence;
  final ProductMatchReason matchReason;

  Map<String, Object> toJson() => {
        'productId': productId,
        'displayName': displayName,
        'matchingScore': matchingScore,
        'confidence': confidence,
        'evidence': evidence.toJson(),
        'matchReason': matchReason.name,
      };
}
