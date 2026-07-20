import 'dart:async';

import '../domain/receipt_ocr_failure.dart';
import '../domain/receipt_ocr_provider.dart';
import '../domain/receipt_ocr_request.dart';
import '../domain/receipt_ocr_result.dart';

class ReceiptOcrService {
  const ReceiptOcrService({required ReceiptOcrProvider provider})
      : _provider = provider;

  final ReceiptOcrProvider _provider;

  ReceiptOcrProviderCapabilities get capabilities => _provider.capabilities;

  Future<ReceiptOcrResult> recognize(ReceiptOcrRequest request) async {
    _validateRequest(request);
    final availability = await _checkAvailability();
    if (!availability.isAvailable) {
      throw ReceiptOcrProviderUnavailable(
        availability.reason ?? 'خدمة التعرف على النص غير متاحة حاليًا.',
      );
    }
    try {
      final operation = _provider.recognize(request);
      final timeout = request.configuration.timeout;
      final result =
          timeout == null ? await operation : await operation.timeout(timeout);
      if (result.text.trim().isEmpty) {
        throw const ReceiptOcrNoTextDetected(
          'لم يتم اكتشاف نص في صورة الإيصال.',
        );
      }
      return result;
    } on ReceiptOcrFailure {
      rethrow;
    } on ReceiptOcrProviderException catch (error) {
      throw _mapProviderFailure(error);
    } on TimeoutException catch (error) {
      throw ReceiptOcrRecognitionFailed(
        'انتهت مهلة التعرف على النص. حاول مجددًا.',
        cause: error,
      );
    } catch (error) {
      throw ReceiptOcrRecognitionFailed(
        'تعذر التعرف على نص الإيصال. حاول مجددًا.',
        cause: error,
      );
    }
  }

  void _validateRequest(ReceiptOcrRequest request) {
    final image = request.image;
    if (image.bytes.isEmpty || image.width <= 0 || image.height <= 0) {
      throw const ReceiptOcrImageUnreadable(
        'صورة الإيصال غير قابلة للقراءة.',
      );
    }
    if (request.preferredLanguages.isEmpty) {
      throw const ReceiptOcrUnsupportedLanguage(
        'حدد لغة واحدة على الأقل للتعرف على النص.',
      );
    }
    final supported = request.preferredLanguages.any(
      _provider.capabilities.supportedLanguages.contains,
    );
    if (!supported) {
      throw const ReceiptOcrUnsupportedLanguage(
        'اللغات المطلوبة غير مدعومة من مزود التعرف الحالي.',
      );
    }
    final timeout = request.configuration.timeout;
    if (timeout != null && timeout <= Duration.zero) {
      throw const ReceiptOcrRecognitionFailed(
        'يجب أن تكون مهلة التعرف على النص أكبر من صفر.',
      );
    }
  }

  Future<ReceiptOcrProviderAvailability> _checkAvailability() async {
    try {
      return await _provider.checkAvailability();
    } on ReceiptOcrProviderException catch (error) {
      throw _mapProviderFailure(error);
    } catch (error) {
      throw ReceiptOcrProviderUnavailable(
        'تعذر التحقق من توفر خدمة التعرف على النص.',
        cause: error,
      );
    }
  }

  ReceiptOcrFailure _mapProviderFailure(ReceiptOcrProviderException error) =>
      switch (error.code) {
        ReceiptOcrProviderErrorCode.permissionDenied =>
          ReceiptOcrPermissionDenied(error.message, cause: error.cause),
        ReceiptOcrProviderErrorCode.imageUnreadable =>
          ReceiptOcrImageUnreadable(error.message, cause: error.cause),
        ReceiptOcrProviderErrorCode.noTextDetected =>
          ReceiptOcrNoTextDetected(error.message, cause: error.cause),
        ReceiptOcrProviderErrorCode.providerUnavailable =>
          ReceiptOcrProviderUnavailable(error.message, cause: error.cause),
        ReceiptOcrProviderErrorCode.recognitionFailed =>
          ReceiptOcrRecognitionFailed(error.message, cause: error.cause),
        ReceiptOcrProviderErrorCode.unsupportedLanguage =>
          ReceiptOcrUnsupportedLanguage(error.message, cause: error.cause),
      };
}
