import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:maqadi_v2/models/receipt_capture_models.dart';
import 'package:maqadi_v2/services/receipt_capture_service.dart';
import 'package:maqadi_v2/services/receipt_image_gateway.dart';

void main() {
  group('ReceiptCaptureService', () {
    late _FakeAcquirer acquirer;
    late _FakeCropper cropper;
    late ReceiptCaptureService service;
    late bool serviceDisposed;

    setUp(() {
      acquirer = _FakeAcquirer();
      cropper = _FakeCropper();
      service = ReceiptCaptureService(
        imageAcquirer: acquirer,
        imageCropper: cropper,
        clock: () => DateTime(2026, 7, 20, 12),
      );
      serviceDisposed = false;
    });

    tearDown(() {
      if (!serviceDisposed) service.dispose();
    });

    test('camera capture validates the image and selects it', () async {
      acquirer.cameraResult = _candidate(
        source: ReceiptAcquisitionSource.camera,
      );

      await service.captureFromCamera();

      expect(acquirer.lastSource, ReceiptAcquisitionSource.camera);
      expect(service.session.status, ReceiptSessionStatus.imageSelected);
      expect(service.session.currentImage!.source,
          ReceiptAcquisitionSource.camera);
    });

    test('gallery selection follows processing then selected transitions',
        () async {
      acquirer.galleryResult = _candidate();
      final statuses = <ReceiptSessionStatus>[];
      service.addListener(() => statuses.add(service.session.status));

      await service.selectFromGallery();

      expect(statuses, [
        ReceiptSessionStatus.processing,
        ReceiptSessionStatus.imageSelected,
      ]);
    });

    test('picker cancellation restores the previous session', () async {
      acquirer.galleryResult = _candidate();
      await service.selectFromGallery();
      final previousImage = service.session.currentImage;
      acquirer.cameraResult = null;

      await service.captureFromCamera();

      expect(service.session.status, ReceiptSessionStatus.imageSelected);
      expect(service.session.currentImage, same(previousImage));
    });

    test('a replacement image replaces both original and current images',
        () async {
      acquirer.galleryResult = _candidate(width: 320, height: 480);
      await service.selectFromGallery();
      acquirer.cameraResult = _candidate(
        width: 420,
        height: 520,
        source: ReceiptAcquisitionSource.camera,
      );

      await service.captureFromCamera();

      expect(service.session.originalImage!.width, 420);
      expect(service.session.currentImage!.height, 520);
      expect(service.session.currentImage!.source,
          ReceiptAcquisitionSource.camera);
    });

    test('rotation edits non-destructively and reset restores the original',
        () async {
      acquirer.galleryResult = _candidate(width: 320, height: 480);
      await service.selectFromGallery();
      final original = service.session.originalImage;

      service.rotateRight();

      expect(service.session.status, ReceiptSessionStatus.editing);
      expect(service.session.currentImage!.width, 480);
      expect(service.session.currentImage!.height, 320);
      expect(service.session.originalImage, same(original));

      service.reset();

      expect(service.session.status, ReceiptSessionStatus.imageSelected);
      expect(service.session.currentImage, same(original));
    });

    test('crop replaces only the editable image', () async {
      acquirer.galleryResult = _candidate(width: 320, height: 480);
      await service.selectFromGallery();
      final original = service.session.originalImage;
      cropper.result = _candidate(width: 260, height: 300);

      await service.crop();

      expect(service.session.status, ReceiptSessionStatus.editing);
      expect(service.session.currentImage!.width, 260);
      expect(service.session.originalImage, same(original));
    });

    test('invalid acquisition enters an error state with no stored image',
        () async {
      acquirer.galleryResult = ReceiptImageCandidate(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'broken.jpg',
        source: ReceiptAcquisitionSource.gallery,
      );

      await service.selectFromGallery();

      expect(service.session.status, ReceiptSessionStatus.error);
      expect(service.session.hasImage, isFalse);
      expect(service.session.errorMessage, isNotEmpty);
    });

    test('next step revalidates the current image and marks it ready',
        () async {
      acquirer.galleryResult = _candidate();
      await service.selectFromGallery();

      final result = await service.prepareNextStep();

      expect(result.width, 320);
      expect(service.session.status, ReceiptSessionStatus.ready);
    });

    test('cancel clears temporary session data', () async {
      acquirer.galleryResult = _candidate();
      await service.selectFromGallery();

      service.cancel();

      expect(service.session.status, ReceiptSessionStatus.cancelled);
      expect(service.session.hasImage, isFalse);
      expect(service.session.currentImage, isNull);
    });

    test('late acquisition is discarded after cancellation', () async {
      acquirer.pendingResult = Completer<ReceiptImageCandidate?>();
      final acquisition = service.selectFromGallery();

      service.cancel();
      acquirer.pendingResult!.complete(_candidate());
      await acquisition;

      expect(service.session.status, ReceiptSessionStatus.cancelled);
      expect(service.session.hasImage, isFalse);
    });

    test('late acquisition is safely discarded after disposal', () async {
      acquirer.pendingResult = Completer<ReceiptImageCandidate?>();
      final acquisition = service.selectFromGallery();

      service.dispose();
      serviceDisposed = true;
      acquirer.pendingResult!.complete(_candidate());
      await acquisition;

      expect(service.session.hasImage, isFalse);
    });
  });
}

ReceiptImageCandidate _candidate({
  int width = 320,
  int height = 480,
  ReceiptAcquisitionSource source = ReceiptAcquisitionSource.gallery,
}) =>
    ReceiptImageCandidate(
      bytes: Uint8List.fromList(
        image.encodePng(image.Image(width: width, height: height)),
      ),
      fileName: 'receipt.png',
      source: source,
    );

class _FakeAcquirer implements ReceiptImageAcquirer {
  ReceiptImageCandidate? cameraResult;
  ReceiptImageCandidate? galleryResult;
  ReceiptAcquisitionSource? lastSource;
  Completer<ReceiptImageCandidate?>? pendingResult;

  @override
  Future<ReceiptImageCandidate?> acquire(
    ReceiptAcquisitionSource source,
  ) async {
    lastSource = source;
    if (pendingResult case final pending?) return pending.future;
    return source == ReceiptAcquisitionSource.camera
        ? cameraResult
        : galleryResult;
  }
}

class _FakeCropper implements ReceiptImageCropper {
  ReceiptImageCandidate? result;

  @override
  Future<ReceiptImageCandidate?> crop(ReceiptImage image) async => result;
}
