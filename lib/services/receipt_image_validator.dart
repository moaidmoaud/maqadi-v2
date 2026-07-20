import 'package:image/image.dart' as image;

import '../models/receipt_capture_models.dart';

abstract interface class ReceiptQualityRule {
  String? validate(ReceiptImageMetadata metadata);
}

class ReceiptImageValidator {
  const ReceiptImageValidator({
    this.minimumWidth = 240,
    this.minimumHeight = 240,
    this.maximumWidth = 20000,
    this.maximumHeight = 20000,
    this.qualityRules = const [],
  });

  final int minimumWidth;
  final int minimumHeight;
  final int maximumWidth;
  final int maximumHeight;
  final List<ReceiptQualityRule> qualityRules;

  ReceiptImage validate(
    ReceiptImageCandidate candidate, {
    required DateTime createdAt,
  }) {
    if (candidate.bytes.isEmpty) {
      throw const ReceiptCaptureException('ملف صورة الإيصال فارغ.');
    }
    final format = _formatFor(candidate.fileName);
    image.Image? decoded;
    try {
      decoded = image.decodeImage(candidate.bytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const ReceiptCaptureException(
        'تعذر قراءة صورة الإيصال. اختر صورة سليمة وحاول مجددًا.',
      );
    }
    if (decoded.width < minimumWidth || decoded.height < minimumHeight) {
      throw ReceiptCaptureException(
        'أبعاد الصورة صغيرة جدًا. الحد الأدنى $minimumWidth × $minimumHeight بكسل.',
      );
    }
    if (decoded.width > maximumWidth || decoded.height > maximumHeight) {
      throw ReceiptCaptureException(
        'أبعاد الصورة كبيرة جدًا. الحد الأعلى $maximumWidth × $maximumHeight بكسل.',
      );
    }
    final metadata = ReceiptImageMetadata(
      format: format,
      width: decoded.width,
      height: decoded.height,
      byteLength: candidate.bytes.length,
    );
    for (final rule in qualityRules) {
      final message = rule.validate(metadata);
      if (message != null && message.trim().isNotEmpty) {
        throw ReceiptCaptureException(message.trim());
      }
    }
    return ReceiptImage(
      bytes: candidate.bytes,
      format: format,
      width: decoded.width,
      height: decoded.height,
      source: candidate.source,
      createdAt: createdAt,
    );
  }

  ReceiptImageFormat _formatFor(String fileName) {
    final name = fileName.trim().toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      return ReceiptImageFormat.jpeg;
    }
    if (name.endsWith('.png')) return ReceiptImageFormat.png;
    if (name.endsWith('.webp')) return ReceiptImageFormat.webp;
    throw const ReceiptCaptureException(
      'صيغة الصورة غير مدعومة. استخدم JPG أو PNG أو WebP.',
    );
  }
}

class ReceiptCaptureException implements Exception {
  const ReceiptCaptureException(this.message);

  final String message;

  @override
  String toString() => message;
}
