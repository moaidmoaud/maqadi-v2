import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:maqadi_v2/models/receipt_capture_models.dart';
import 'package:maqadi_v2/services/receipt_image_validator.dart';

void main() {
  group('ReceiptImageValidator', () {
    const validator = ReceiptImageValidator();
    final createdAt = DateTime(2026, 7, 20);

    test('accepts a supported, decodable image and reads its dimensions', () {
      final result = validator.validate(
        _candidate(width: 320, height: 480),
        createdAt: createdAt,
      );

      expect(result.format, ReceiptImageFormat.png);
      expect(result.width, 320);
      expect(result.height, 480);
      expect(result.createdAt, createdAt);
    });

    test('rejects an empty image', () {
      expect(
        () => validator.validate(
          ReceiptImageCandidate(
            bytes: Uint8List(0),
            fileName: 'receipt.png',
            source: ReceiptAcquisitionSource.gallery,
          ),
          createdAt: createdAt,
        ),
        throwsA(isA<ReceiptCaptureException>()),
      );
    });

    test('rejects unsupported formats', () {
      expect(
        () => validator.validate(
          _candidate(fileName: 'receipt.gif'),
          createdAt: createdAt,
        ),
        throwsA(
          isA<ReceiptCaptureException>().having(
            (error) => error.message,
            'message',
            contains('غير مدعومة'),
          ),
        ),
      );
    });

    test('rejects corrupt image bytes', () {
      expect(
        () => validator.validate(
          ReceiptImageCandidate(
            bytes: Uint8List.fromList([1, 2, 3]),
            fileName: 'receipt.jpg',
            source: ReceiptAcquisitionSource.camera,
          ),
          createdAt: createdAt,
        ),
        throwsA(isA<ReceiptCaptureException>()),
      );
    });

    test('rejects dimensions below the configured minimum', () {
      expect(
        () => validator.validate(
          _candidate(width: 100, height: 100),
          createdAt: createdAt,
        ),
        throwsA(
          isA<ReceiptCaptureException>().having(
            (error) => error.message,
            'message',
            contains('صغيرة جدًا'),
          ),
        ),
      );
    });

    test('supports future quality rules without enabling one by default', () {
      const qualityValidator = ReceiptImageValidator(
        qualityRules: [_AlwaysRejectRule()],
      );

      expect(
        () => qualityValidator.validate(
          _candidate(),
          createdAt: createdAt,
        ),
        throwsA(
          isA<ReceiptCaptureException>().having(
            (error) => error.message,
            'message',
            'quality rule failed',
          ),
        ),
      );
    });
  });
}

ReceiptImageCandidate _candidate({
  int width = 320,
  int height = 480,
  String fileName = 'receipt.png',
}) =>
    ReceiptImageCandidate(
      bytes: Uint8List.fromList(
        image.encodePng(image.Image(width: width, height: height)),
      ),
      fileName: fileName,
      source: ReceiptAcquisitionSource.gallery,
    );

class _AlwaysRejectRule implements ReceiptQualityRule {
  const _AlwaysRejectRule();

  @override
  String? validate(ReceiptImageMetadata metadata) => 'quality rule failed';
}
