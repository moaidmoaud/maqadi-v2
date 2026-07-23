enum ProductRankingFactorType {
  exactNormalizedMatch,
  canonicalNameMatch,
  aliasMatch,
  tokenCoverage,
  aliasSpecificity,
}

class ProductRankingFactor {
  const ProductRankingFactor({
    required this.type,
    required this.value,
    required this.weight,
    required this.contribution,
  })  : assert(value >= 0 && value <= 1),
        assert(weight >= 0 && weight <= 1),
        assert(contribution >= 0 && contribution <= 1);

  factory ProductRankingFactor.fromJson(Map<String, Object?> json) =>
      ProductRankingFactor(
        type: ProductRankingFactorType.values.byName(json['type']! as String),
        value: (json['value']! as num).toDouble(),
        weight: (json['weight']! as num).toDouble(),
        contribution: (json['contribution']! as num).toDouble(),
      );

  final ProductRankingFactorType type;
  final double value;
  final double weight;
  final double contribution;

  Map<String, Object> toJson() => {
        'type': type.name,
        'value': value,
        'weight': weight,
        'contribution': contribution,
      };
}

class ProductCandidateRankingEvidence {
  ProductCandidateRankingEvidence({
    required this.productId,
    required this.originalOrder,
    required this.rank,
    required this.finalScore,
    required Iterable<ProductRankingFactor> factors,
  }) : factors = List.unmodifiable(factors);

  factory ProductCandidateRankingEvidence.fromJson(
    Map<String, Object?> json,
  ) =>
      ProductCandidateRankingEvidence(
        productId: json['productId']! as String,
        originalOrder: json['originalOrder']! as int,
        rank: json['rank']! as int,
        finalScore: (json['finalScore']! as num).toDouble(),
        factors: (json['factors']! as List<Object?>).map(
          (value) => ProductRankingFactor.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );

  final String productId;
  final int originalOrder;
  final int rank;
  final double finalScore;
  final List<ProductRankingFactor> factors;

  Map<String, Object> toJson() => {
        'productId': productId,
        'originalOrder': originalOrder,
        'rank': rank,
        'finalScore': finalScore,
        'factors': [for (final value in factors) value.toJson()],
      };
}
