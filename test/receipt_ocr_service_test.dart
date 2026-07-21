import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/receipt_capture_models.dart';
import 'package:maqadi_v2/receipt_ocr/application/receipt_ocr_service.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_failure.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_provider.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_request.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';

void main() {
  group('ReceiptOcrService', () {
    late _MockReceiptOcrProvider provider;
    late ReceiptOcrService service;

    setUp(() {
      provider = _MockReceiptOcrProvider();
      service = ReceiptOcrService(provider: provider);
    });

    test('depends on the provider abstraction and exposes capabilities', () {
      expect(provider, isA<ReceiptOcrProvider>());
      expect(
        service.capabilities.supportedLanguages,
        contains(ReceiptOcrLanguage.english),
      );
    });

    test('returns a provider-independent structured OCR result', () async {
      provider.result = _structuredResult;
      final request = _request();

      final result = await service.recognize(request);

      expect(result.text, 'Market\nMilk 10');
      expect(result.blocks.single.lines.last.words.first.text, 'Milk');
      expect(result.blocks.single.lines.last.words.last.confidence, 0.95);
      expect(result.blocks.single.region!.width, 200);
      expect(provider.lastRequest, same(request));
    });

    test('maps an empty provider result to no text detected', () async {
      provider.result = const ReceiptOcrResult(text: '  ', blocks: []);

      await expectLater(
        service.recognize(_request()),
        throwsA(isA<ReceiptOcrNoTextDetected>()),
      );
    });

    test('rejects an unreadable request before calling the provider', () async {
      final invalid = _request(
        image: ReceiptImage(
          bytes: Uint8List(0),
          format: ReceiptImageFormat.jpeg,
          width: 0,
          height: 0,
          source: ReceiptAcquisitionSource.gallery,
          createdAt: DateTime(2026, 7, 21),
        ),
      );

      await expectLater(
        service.recognize(invalid),
        throwsA(isA<ReceiptOcrImageUnreadable>()),
      );
      expect(provider.recognitionCalls, 0);
    });

    test('reports an unavailable provider without recognizing', () async {
      provider.availability = const ReceiptOcrProviderAvailability.unavailable(
        'provider offline',
      );

      await expectLater(
        service.recognize(_request()),
        throwsA(
          isA<ReceiptOcrProviderUnavailable>().having(
            (failure) => failure.message,
            'message',
            'provider offline',
          ),
        ),
      );
      expect(provider.recognitionCalls, 0);
    });

    test('rejects a language unsupported by the selected provider', () async {
      await expectLater(
        service.recognize(
          _request(languages: const [ReceiptOcrLanguage.arabic]),
        ),
        throwsA(isA<ReceiptOcrUnsupportedLanguage>()),
      );
      expect(provider.availabilityCalls, 0);
    });

    test('accepts mixed language preferences when one is supported', () async {
      provider.result = _structuredResult;

      final result = await service.recognize(_request());

      expect(result, same(_structuredResult));
      expect(provider.recognitionCalls, 1);
    });

    final failureCases = <ReceiptOcrProviderErrorCode, Type>{
      ReceiptOcrProviderErrorCode.permissionDenied: ReceiptOcrPermissionDenied,
      ReceiptOcrProviderErrorCode.imageUnreadable: ReceiptOcrImageUnreadable,
      ReceiptOcrProviderErrorCode.noTextDetected: ReceiptOcrNoTextDetected,
      ReceiptOcrProviderErrorCode.providerUnavailable:
          ReceiptOcrProviderUnavailable,
      ReceiptOcrProviderErrorCode.recognitionFailed:
          ReceiptOcrRecognitionFailed,
      ReceiptOcrProviderErrorCode.unsupportedLanguage:
          ReceiptOcrUnsupportedLanguage,
    };
    for (final failureCase in failureCases.entries) {
      test('maps provider ${failureCase.key.name} without leaking it',
          () async {
        provider.error = ReceiptOcrProviderException(
          failureCase.key,
          'mapped message',
        );

        await expectLater(
          service.recognize(_request()),
          throwsA(
            isA<ReceiptOcrFailure>()
                .having(
                  (failure) => failure.runtimeType,
                  'runtime type',
                  failureCase.value,
                )
                .having(
                  (failure) => failure.message,
                  'message',
                  'mapped message',
                ),
          ),
        );
      });
    }

    test('maps unexpected provider exceptions to recognition failed', () async {
      provider.unexpectedError = StateError('SDK detail');

      await expectLater(
        service.recognize(_request()),
        throwsA(isA<ReceiptOcrRecognitionFailed>()),
      );
    });

    test('maps a configured timeout to recognition failed', () async {
      provider.pendingResult = Completer<ReceiptOcrResult>();

      await expectLater(
        service.recognize(
          _request(
            configuration: const ReceiptOcrConfiguration(
              timeout: Duration(milliseconds: 1),
            ),
          ),
        ),
        throwsA(isA<ReceiptOcrRecognitionFailed>()),
      );
      expect(provider.cancellationCalls, 1);
    });

    test('dispose cancels provider work so temporary resources can close',
        () async {
      await service.dispose();

      expect(provider.cancellationCalls, 1);
    });
  });
}

ReceiptOcrRequest _request({
  ReceiptImage? image,
  List<ReceiptOcrLanguage> languages = const [
    ReceiptOcrLanguage.arabic,
    ReceiptOcrLanguage.english,
  ],
  ReceiptOcrConfiguration configuration = const ReceiptOcrConfiguration(),
}) =>
    ReceiptOcrRequest(
      image: image ?? _validImage(),
      preferredLanguages: languages,
      configuration: configuration,
    );

ReceiptImage _validImage() => ReceiptImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      format: ReceiptImageFormat.jpeg,
      width: 640,
      height: 960,
      source: ReceiptAcquisitionSource.gallery,
      createdAt: DateTime(2026, 7, 21),
    );

const _structuredResult = ReceiptOcrResult(
  text: 'Market\nMilk 10',
  blocks: [
    ReceiptOcrBlock(
      text: 'Market\nMilk 10',
      region: ReceiptOcrRegion(x: 10, y: 20, width: 200, height: 80),
      lines: [
        ReceiptOcrLine(
          text: 'Market',
          words: [ReceiptOcrWord(text: 'Market')],
        ),
        ReceiptOcrLine(
          text: 'Milk 10',
          words: [
            ReceiptOcrWord(text: 'Milk'),
            ReceiptOcrWord(text: '10', confidence: 0.95),
          ],
        ),
      ],
    ),
  ],
);

class _MockReceiptOcrProvider
    implements ReceiptOcrProvider, CancellableReceiptOcrProvider {
  @override
  ReceiptOcrProviderCapabilities capabilities =
      const ReceiptOcrProviderCapabilities(
    supportedLanguages: {ReceiptOcrLanguage.english},
    providesConfidence: true,
    providesRegions: true,
  );

  ReceiptOcrProviderAvailability availability =
      const ReceiptOcrProviderAvailability.available();
  ReceiptOcrResult result = _structuredResult;
  ReceiptOcrProviderException? error;
  Object? unexpectedError;
  Completer<ReceiptOcrResult>? pendingResult;
  ReceiptOcrRequest? lastRequest;
  int availabilityCalls = 0;
  int recognitionCalls = 0;
  int cancellationCalls = 0;

  @override
  Future<void> cancelPendingRecognitions() async {
    cancellationCalls++;
  }

  @override
  Future<ReceiptOcrProviderAvailability> checkAvailability() async {
    availabilityCalls++;
    return availability;
  }

  @override
  Future<ReceiptOcrResult> recognize(ReceiptOcrRequest request) async {
    recognitionCalls++;
    lastRequest = request;
    if (error case final providerError?) throw providerError;
    if (unexpectedError case final otherError?) throw otherError;
    if (pendingResult case final pending?) return pending.future;
    return result;
  }
}
