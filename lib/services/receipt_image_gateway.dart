import 'dart:io';

import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/receipt_capture_models.dart';

abstract interface class ReceiptImageAcquirer {
  Future<ReceiptImageCandidate?> acquire(ReceiptAcquisitionSource source);
}

abstract interface class ReceiptImageCropper {
  Future<ReceiptImageCandidate?> crop(ReceiptImage image);
}

class PlatformReceiptImageAcquirer implements ReceiptImageAcquirer {
  PlatformReceiptImageAcquirer({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<ReceiptImageCandidate?> acquire(
    ReceiptAcquisitionSource source,
  ) async {
    final selected = await _picker.pickImage(
      source: source == ReceiptAcquisitionSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (selected == null) return null;
    return ReceiptImageCandidate(
      bytes: await selected.readAsBytes(),
      fileName: selected.name,
      source: source,
    );
  }
}

class PlatformReceiptImageCropper implements ReceiptImageCropper {
  PlatformReceiptImageCropper({ImageCropper? cropper})
      : _cropper = cropper ?? ImageCropper();

  final ImageCropper _cropper;

  @override
  Future<ReceiptImageCandidate?> crop(ReceiptImage image) async {
    final sourceFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'maqadi_receipt_${DateTime.now().microsecondsSinceEpoch}'
      '.${image.fileExtension}',
    );
    await sourceFile.writeAsBytes(image.bytes, flush: true);
    try {
      final cropped = await _cropper.cropImage(
        sourcePath: sourceFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'قص الإيصال',
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'قص الإيصال',
            doneButtonTitle: 'تم',
            cancelButtonTitle: 'إلغاء',
          ),
        ],
      );
      if (cropped == null) return null;
      return ReceiptImageCandidate(
        bytes: await cropped.readAsBytes(),
        fileName: cropped.path,
        source: image.source,
      );
    } finally {
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    }
  }
}
