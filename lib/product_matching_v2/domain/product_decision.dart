enum ProductDecisionStatus { matched, needsReview, ambiguous, noMatch }

class ProductConfidenceCalculation {
  const ProductConfidenceCalculation({
    required this.rankingScore,
    required this.runnerUpScore,
    required this.separation,
    required this.evidenceQuality,
    required this.rankingScoreWeight,
    required this.separationWeight,
    required this.evidenceQualityWeight,
    required this.finalConfidence,
  });

  factory ProductConfidenceCalculation.fromJson(Map<String, Object?> json) =>
      ProductConfidenceCalculation(
        rankingScore: (json['rankingScore']! as num).toDouble(),
        runnerUpScore: (json['runnerUpScore'] as num?)?.toDouble(),
        separation: (json['separation']! as num).toDouble(),
        evidenceQuality: (json['evidenceQuality']! as num).toDouble(),
        rankingScoreWeight: (json['rankingScoreWeight']! as num).toDouble(),
        separationWeight: (json['separationWeight']! as num).toDouble(),
        evidenceQualityWeight:
            (json['evidenceQualityWeight']! as num).toDouble(),
        finalConfidence: (json['finalConfidence']! as num).toDouble(),
      );

  final double rankingScore;
  final double? runnerUpScore;
  final double separation;
  final double evidenceQuality;
  final double rankingScoreWeight;
  final double separationWeight;
  final double evidenceQualityWeight;
  final double finalConfidence;

  Map<String, Object?> toJson() => {
        'rankingScore': rankingScore,
        'runnerUpScore': runnerUpScore,
        'separation': separation,
        'evidenceQuality': evidenceQuality,
        'rankingScoreWeight': rankingScoreWeight,
        'separationWeight': separationWeight,
        'evidenceQualityWeight': evidenceQualityWeight,
        'finalConfidence': finalConfidence,
      };
}
