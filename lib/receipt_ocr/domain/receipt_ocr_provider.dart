import 'receipt_ocr_request.dart';
import 'receipt_ocr_result.dart';

class ReceiptOcrProviderCapabilities {
  const ReceiptOcrProviderCapabilities({
    required this.supportedLanguages,
    required this.providesConfidence,
    required this.providesRegions,
  });

  final Set<ReceiptOcrLanguage> supportedLanguages;
  final bool providesConfidence;
  final bool providesRegions;
}

class ReceiptOcrProviderAvailability {
  const ReceiptOcrProviderAvailability.available()
      : isAvailable = true,
        reason = null;

  const ReceiptOcrProviderAvailability.unavailable([this.reason])
      : isAvailable = false;

  final bool isAvailable;
  final String? reason;
}

enum ReceiptOcrProviderErrorCode {
  permissionDenied,
  imageUnreadable,
  noTextDetected,
  providerUnavailable,
  recognitionFailed,
  unsupportedLanguage,
}

class ReceiptOcrProviderException implements Exception {
  const ReceiptOcrProviderException(
    this.code,
    this.message, {
    this.cause,
  });

  final ReceiptOcrProviderErrorCode code;
  final String message;
  final Object? cause;
}

abstract interface class ReceiptOcrProvider {
  ReceiptOcrProviderCapabilities get capabilities;

  Future<ReceiptOcrProviderAvailability> checkAvailability();

  Future<ReceiptOcrResult> recognize(ReceiptOcrRequest request);
}
