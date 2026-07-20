sealed class ReceiptOcrFailure implements Exception {
  const ReceiptOcrFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

final class ReceiptOcrPermissionDenied extends ReceiptOcrFailure {
  const ReceiptOcrPermissionDenied(super.message, {super.cause});
}

final class ReceiptOcrImageUnreadable extends ReceiptOcrFailure {
  const ReceiptOcrImageUnreadable(super.message, {super.cause});
}

final class ReceiptOcrNoTextDetected extends ReceiptOcrFailure {
  const ReceiptOcrNoTextDetected(super.message, {super.cause});
}

final class ReceiptOcrProviderUnavailable extends ReceiptOcrFailure {
  const ReceiptOcrProviderUnavailable(super.message, {super.cause});
}

final class ReceiptOcrRecognitionFailed extends ReceiptOcrFailure {
  const ReceiptOcrRecognitionFailed(super.message, {super.cause});
}

final class ReceiptOcrUnsupportedLanguage extends ReceiptOcrFailure {
  const ReceiptOcrUnsupportedLanguage(super.message, {super.cause});
}
