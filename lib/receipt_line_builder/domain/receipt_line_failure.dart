enum ReceiptLineFailureCode {
  duplicateElementId,
  invalidGeometry,
  invalidReference,
  duplicateRoleAssignment,
  groupingFailed,
}

class ReceiptLineFailure implements Exception {
  const ReceiptLineFailure({
    required this.code,
    required this.message,
    this.elementId,
    this.cause,
  });

  final ReceiptLineFailureCode code;
  final String message;
  final String? elementId;
  final Object? cause;

  @override
  String toString() => message;
}
