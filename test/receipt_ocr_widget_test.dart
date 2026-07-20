import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/receipt_capture_models.dart';
import 'package:maqadi_v2/receipt_ocr/application/receipt_ocr_service.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_provider.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_request.dart';
import 'package:maqadi_v2/receipt_ocr/domain/receipt_ocr_result.dart';
import 'package:maqadi_v2/receipt_ocr/presentation/receipt_ocr_screen.dart';

void main() {
  testWidgets('shows loading while OCR is pending', (tester) async {
    final provider = _QueuedProvider([
      (_) => Completer<ReceiptOcrResult>().future,
    ]);

    await tester.pumpWidget(_app(provider));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('جارٍ التعرف على النص...'), findsOneWidget);
  });

  testWidgets('renders structured OCR success without parsing the receipt',
      (tester) async {
    final provider = _QueuedProvider([(_) async => _result]);

    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();

    expect(find.text('اكتمل التعرف على النص'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('receipt-ocr-result-text')), findsOneWidget);
    expect(find.text('Market\nMilk 10'), findsWidgets);
    expect(find.text('1 كتلة نصية'), findsOneWidget);
  });

  testWidgets('shows mapped failure and retries through the service',
      (tester) async {
    final provider = _QueuedProvider([
      (_) => throw const ReceiptOcrProviderException(
            ReceiptOcrProviderErrorCode.providerUnavailable,
            'الخدمة غير متاحة للاختبار.',
          ),
      (_) async => _result,
    ]);

    await tester.pumpWidget(_app(provider));
    await tester.pumpAndSettle();

    expect(find.text('الخدمة غير متاحة للاختبار.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('receipt-ocr-retry')));
    await tester.pumpAndSettle();

    expect(find.text('اكتمل التعرف على النص'), findsOneWidget);
    expect(provider.recognitionCalls, 2);
  });
}

Widget _app(ReceiptOcrProvider provider) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: ReceiptOcrScreen(
          service: ReceiptOcrService(provider: provider),
          request: ReceiptOcrRequest(image: _image()),
        ),
      ),
    );

ReceiptImage _image() => ReceiptImage(
      bytes: Uint8List.fromList([1, 2, 3]),
      format: ReceiptImageFormat.jpeg,
      width: 640,
      height: 960,
      source: ReceiptAcquisitionSource.gallery,
      createdAt: DateTime(2026, 7, 21),
    );

const _result = ReceiptOcrResult(
  text: 'Market\nMilk 10',
  blocks: [
    ReceiptOcrBlock(
      text: 'Market\nMilk 10',
      lines: [
        ReceiptOcrLine(
          text: 'Milk 10',
          words: [ReceiptOcrWord(text: 'Milk'), ReceiptOcrWord(text: '10')],
        ),
      ],
    ),
  ],
);

class _QueuedProvider implements ReceiptOcrProvider {
  _QueuedProvider(this.responses);

  final List<Future<ReceiptOcrResult> Function(ReceiptOcrRequest)> responses;
  int recognitionCalls = 0;

  @override
  ReceiptOcrProviderCapabilities get capabilities =>
      const ReceiptOcrProviderCapabilities(
        supportedLanguages: {ReceiptOcrLanguage.english},
        providesConfidence: true,
        providesRegions: true,
      );

  @override
  Future<ReceiptOcrProviderAvailability> checkAvailability() async =>
      const ReceiptOcrProviderAvailability.available();

  @override
  Future<ReceiptOcrResult> recognize(ReceiptOcrRequest request) {
    final response = responses[recognitionCalls];
    recognitionCalls++;
    return response(request);
  }
}
