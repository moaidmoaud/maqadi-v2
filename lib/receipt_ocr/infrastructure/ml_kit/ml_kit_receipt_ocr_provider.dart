import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/receipt_ocr_provider.dart';
import '../../domain/receipt_ocr_request.dart';
import '../../domain/receipt_ocr_result.dart';
import 'ml_kit_ocr_result_mapper.dart';

class MlKitReceiptOcrProvider
    implements ReceiptOcrProvider, CancellableReceiptOcrProvider {
  MlKitReceiptOcrProvider({
    MlKitOcrResultMapper mapper = const MlKitOcrResultMapper(),
  }) : _mapper = mapper;

  final MlKitOcrResultMapper _mapper;
  final Set<_MlKitRecognitionResources> _activeResources = {};
  int _fileCounter = 0;

  @override
  ReceiptOcrProviderCapabilities get capabilities =>
      const ReceiptOcrProviderCapabilities(
        supportedLanguages: {ReceiptOcrLanguage.english},
        providesConfidence: true,
        providesRegions: true,
      );

  @override
  Future<ReceiptOcrProviderAvailability> checkAvailability() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const ReceiptOcrProviderAvailability.unavailable(
        'التعرف على النص متاح على Android وiOS فقط.',
      );
    }
    return const ReceiptOcrProviderAvailability.available();
  }

  @override
  Future<ReceiptOcrResult> recognize(ReceiptOcrRequest request) async {
    _fileCounter++;
    final imageFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'maqadi_ocr_${DateTime.now().microsecondsSinceEpoch}'
      '_$_fileCounter.${request.image.fileExtension}',
    );
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final resources = _MlKitRecognitionResources(imageFile, recognizer);
    _activeResources.add(resources);
    try {
      await imageFile.writeAsBytes(request.image.bytes, flush: true);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(imageFile.path),
      );
      return _mapper.map(recognized);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    } on FileSystemException catch (error) {
      throw ReceiptOcrProviderException(
        ReceiptOcrProviderErrorCode.imageUnreadable,
        'تعذر تجهيز صورة الإيصال للتعرف على النص.',
        cause: error,
      );
    } on ReceiptOcrProviderException {
      rethrow;
    } catch (error) {
      throw ReceiptOcrProviderException(
        ReceiptOcrProviderErrorCode.recognitionFailed,
        'فشل مزود التعرف على النص في معالجة الصورة.',
        cause: error,
      );
    } finally {
      try {
        await resources.cleanup();
      } finally {
        _activeResources.remove(resources);
      }
    }
  }

  @override
  Future<void> cancelPendingRecognitions() async {
    final resources = _activeResources.toList(growable: false);
    await Future.wait(resources.map((resource) => resource.cleanup()));
  }

  ReceiptOcrProviderException _mapPlatformException(PlatformException error) {
    final code = error.code.toLowerCase();
    if (code.contains('permission')) {
      return ReceiptOcrProviderException(
        ReceiptOcrProviderErrorCode.permissionDenied,
        'لا يوجد إذن كافٍ لتشغيل التعرف على النص.',
        cause: error,
      );
    }
    if (code.contains('image') || code.contains('invalid')) {
      return ReceiptOcrProviderException(
        ReceiptOcrProviderErrorCode.imageUnreadable,
        'لم يتمكن مزود التعرف من قراءة الصورة.',
        cause: error,
      );
    }
    if (code.contains('model') || code.contains('unavailable')) {
      return ReceiptOcrProviderException(
        ReceiptOcrProviderErrorCode.providerUnavailable,
        'نموذج التعرف على النص غير متاح حاليًا.',
        cause: error,
      );
    }
    if (code.contains('language') || code.contains('script')) {
      return ReceiptOcrProviderException(
        ReceiptOcrProviderErrorCode.unsupportedLanguage,
        'اللغة المطلوبة غير مدعومة من مزود التعرف الحالي.',
        cause: error,
      );
    }
    return ReceiptOcrProviderException(
      ReceiptOcrProviderErrorCode.recognitionFailed,
      'فشل مزود التعرف على النص في معالجة الصورة.',
      cause: error,
    );
  }
}

class _MlKitRecognitionResources {
  _MlKitRecognitionResources(this.imageFile, this.recognizer);

  final File imageFile;
  final TextRecognizer recognizer;
  Future<void>? _cleanup;

  Future<void> cleanup() => _cleanup ??= _performCleanup();

  Future<void> _performCleanup() async {
    Object? closeError;
    StackTrace? closeStackTrace;
    try {
      await recognizer.close();
    } catch (error, stackTrace) {
      closeError = error;
      closeStackTrace = stackTrace;
    }
    try {
      if (await imageFile.exists()) await imageFile.delete();
    } finally {
      if (closeError != null) {
        Error.throwWithStackTrace(closeError, closeStackTrace!);
      }
    }
  }
}
