class ReceiptLineEvidence {
  ReceiptLineEvidence({
    required this.anchorElementId,
    required Iterable<String> attachedElementIds,
    required Map<String, double> normalizedVerticalDistances,
    required Map<String, double> normalizedHorizontalDistances,
    required Map<String, double> overlapMetrics,
    required Map<String, String> columnEvidence,
    required this.appliedGroupingRule,
    required Map<String, String> rejectedCandidates,
    required Iterable<String> confidenceFactors,
    required this.summary,
  })  : attachedElementIds = List.unmodifiable(attachedElementIds),
        normalizedVerticalDistances =
            Map.unmodifiable(normalizedVerticalDistances),
        normalizedHorizontalDistances =
            Map.unmodifiable(normalizedHorizontalDistances),
        overlapMetrics = Map.unmodifiable(overlapMetrics),
        columnEvidence = Map.unmodifiable(columnEvidence),
        rejectedCandidates = Map.unmodifiable(rejectedCandidates),
        confidenceFactors = List.unmodifiable(confidenceFactors);

  final String? anchorElementId;
  final List<String> attachedElementIds;
  final Map<String, double> normalizedVerticalDistances;
  final Map<String, double> normalizedHorizontalDistances;
  final Map<String, double> overlapMetrics;
  final Map<String, String> columnEvidence;
  final String appliedGroupingRule;
  final Map<String, String> rejectedCandidates;
  final List<String> confidenceFactors;
  final String summary;
}
