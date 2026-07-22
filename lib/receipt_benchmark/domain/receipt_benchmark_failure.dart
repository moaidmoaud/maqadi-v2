enum ReceiptBenchmarkFailureCode {
  invalidDefinition,
  understandingFailed,
  lineBuilderFailed,
  comparisonFailed,
}

class ReceiptBenchmarkFailure implements Exception {
  const ReceiptBenchmarkFailure({
    required this.code,
    required this.message,
    this.cause,
  });

  final ReceiptBenchmarkFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
