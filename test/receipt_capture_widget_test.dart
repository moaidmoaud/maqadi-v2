import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:maqadi_v2/models/receipt_capture_models.dart';
import 'package:maqadi_v2/screens/receipt_capture_screen.dart';
import 'package:maqadi_v2/services/receipt_capture_service.dart';
import 'package:maqadi_v2/services/receipt_image_gateway.dart';

void main() {
  testWidgets('shows empty state and acquisition actions', (tester) async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    await _pumpScreen(tester, fixture);

    expect(find.text('لا توجد صورة محددة'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-camera')), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-gallery')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('receipt-next')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('gallery selection displays image and editing controls',
      (tester) async {
    final fixture = _Fixture()..acquirer.galleryResult = _candidate();
    addTearDown(fixture.dispose);
    await _pumpScreen(tester, fixture);

    await tester.tap(find.byKey(const ValueKey('receipt-gallery')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('receipt-image-preview')), findsOneWidget);
    expect(find.text('تم اختيار الصورة'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('receipt-rotate-left')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('camera failure displays the service error state',
      (tester) async {
    final fixture = _Fixture()
      ..acquirer.cameraResult = ReceiptImageCandidate(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'broken.jpg',
        source: ReceiptAcquisitionSource.camera,
      );
    addTearDown(fixture.dispose);
    await _pumpScreen(tester, fixture);

    await tester.tap(find.byKey(const ValueKey('receipt-camera')));
    await tester.pumpAndSettle();

    expect(find.text('تعذر تجهيز الصورة'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsWidgets);
  });

  testWidgets('rotate, reset, and next actions update visible state',
      (tester) async {
    final fixture = _Fixture()..acquirer.galleryResult = _candidate();
    addTearDown(fixture.dispose);
    await _pumpScreen(tester, fixture);
    await tester.tap(find.byKey(const ValueKey('receipt-gallery')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('receipt-rotate-right')));
    await tester.pump();
    expect(find.text('تم تعديل الصورة'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('receipt-reset')));
    await tester.pump();
    expect(find.text('تم اختيار الصورة'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('receipt-next')));
    await tester.tap(find.byKey(const ValueKey('receipt-next')));
    await tester.pumpAndSettle();
    expect(find.text('الصورة جاهزة'), findsOneWidget);
    expect(find.text('صورة الإيصال جاهزة للخطوة التالية.'), findsOneWidget);
  });
}

Future<void> _pumpScreen(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(fixture.widget());
}

ReceiptImageCandidate _candidate() => ReceiptImageCandidate(
      bytes: Uint8List.fromList(
        image.encodePng(image.Image(width: 320, height: 480)),
      ),
      fileName: 'receipt.png',
      source: ReceiptAcquisitionSource.gallery,
    );

class _Fixture {
  _Fixture() {
    acquirer = _FakeAcquirer();
    cropper = _FakeCropper();
    service = ReceiptCaptureService(
      imageAcquirer: acquirer,
      imageCropper: cropper,
      clock: () => DateTime(2026, 7, 20),
    );
  }

  late final _FakeAcquirer acquirer;
  late final _FakeCropper cropper;
  late final ReceiptCaptureService service;

  Widget widget() => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ReceiptCaptureScreen(service: service),
        ),
      );

  void dispose() {
    service.dispose();
  }
}

class _FakeAcquirer implements ReceiptImageAcquirer {
  ReceiptImageCandidate? cameraResult;
  ReceiptImageCandidate? galleryResult;

  @override
  Future<ReceiptImageCandidate?> acquire(
    ReceiptAcquisitionSource source,
  ) async =>
      source == ReceiptAcquisitionSource.camera ? cameraResult : galleryResult;
}

class _FakeCropper implements ReceiptImageCropper {
  ReceiptImageCandidate? result;

  @override
  Future<ReceiptImageCandidate?> crop(ReceiptImage image) async => result;
}
