class ReceiptCalibrationPolicy {
  const ReceiptCalibrationPolicy({
    this.rowVerticalDistanceTolerance = 0.75,
    this.rowMinimumOverlapRatio = 0.3,
    this.columnGapTolerance = 8.0,
  });

  final double rowVerticalDistanceTolerance;
  final double rowMinimumOverlapRatio;
  final double columnGapTolerance;

  Map<String, double> get values => Map.unmodifiable({
        'rowVerticalDistanceTolerance': rowVerticalDistanceTolerance,
        'rowMinimumOverlapRatio': rowMinimumOverlapRatio,
        'columnGapTolerance': columnGapTolerance,
      });

  bool get isValid =>
      rowVerticalDistanceTolerance.isFinite &&
      rowVerticalDistanceTolerance >= 0 &&
      rowMinimumOverlapRatio.isFinite &&
      rowMinimumOverlapRatio >= 0 &&
      rowMinimumOverlapRatio <= 1 &&
      columnGapTolerance.isFinite &&
      columnGapTolerance >= 0;
}
