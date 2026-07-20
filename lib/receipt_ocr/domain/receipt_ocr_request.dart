import '../../models/receipt_capture_models.dart';

enum ReceiptOcrLanguage {
  arabic('ar'),
  english('en');

  const ReceiptOcrLanguage(this.code);

  final String code;
}

class ReceiptOcrConfiguration {
  const ReceiptOcrConfiguration({this.timeout});

  final Duration? timeout;
}

class ReceiptOcrRequest {
  const ReceiptOcrRequest({
    required this.image,
    this.preferredLanguages = const [
      ReceiptOcrLanguage.arabic,
      ReceiptOcrLanguage.english,
    ],
    this.configuration = const ReceiptOcrConfiguration(),
  });

  final ReceiptImage image;
  final List<ReceiptOcrLanguage> preferredLanguages;
  final ReceiptOcrConfiguration configuration;
}
