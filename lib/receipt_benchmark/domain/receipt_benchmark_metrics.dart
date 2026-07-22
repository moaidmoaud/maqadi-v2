class ReceiptBenchmarkMetrics {
  const ReceiptBenchmarkMetrics({
    required this.understandingAccuracy,
    required this.lineGroupingPrecision,
    required this.lineGroupingRecall,
    required this.lineGroupingF1,
    required this.correctLineCount,
    required this.expectedLineCount,
    required this.actualLineCount,
    required this.unassignedCount,
    required this.misclassifiedElementCount,
    required this.manualCorrectionsEstimate,
  });

  final double understandingAccuracy;
  final double lineGroupingPrecision;
  final double lineGroupingRecall;
  final double lineGroupingF1;
  final int correctLineCount;
  final int expectedLineCount;
  final int actualLineCount;
  final int unassignedCount;
  final int misclassifiedElementCount;
  final int manualCorrectionsEstimate;
}
