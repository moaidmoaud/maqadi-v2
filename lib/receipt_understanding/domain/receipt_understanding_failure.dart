enum ReceiptUnderstandingFailureCode {
  invalidOcrResult,
  classificationFailed,
}

class ReceiptUnderstandingFailure implements Exception {
  const ReceiptUnderstandingFailure({
    required this.code,
    required this.message,
    this.cause,
  });

  final ReceiptUnderstandingFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
