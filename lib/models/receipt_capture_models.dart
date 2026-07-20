import 'dart:typed_data';

enum ReceiptAcquisitionSource { camera, gallery }

enum ReceiptImageFormat { jpeg, png, webp }

enum ReceiptSessionStatus {
  idle,
  imageSelected,
  editing,
  ready,
  processing,
  error,
  cancelled,
}

class ReceiptImageCandidate {
  const ReceiptImageCandidate({
    required this.bytes,
    required this.fileName,
    required this.source,
  });

  final Uint8List bytes;
  final String fileName;
  final ReceiptAcquisitionSource source;
}

class ReceiptImage {
  const ReceiptImage({
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
    required this.source,
    required this.createdAt,
  });

  final Uint8List bytes;
  final ReceiptImageFormat format;
  final int width;
  final int height;
  final ReceiptAcquisitionSource source;
  final DateTime createdAt;

  String get fileExtension => switch (format) {
        ReceiptImageFormat.jpeg => 'jpg',
        ReceiptImageFormat.png => 'png',
        ReceiptImageFormat.webp => 'webp',
      };
}

class ReceiptSession {
  const ReceiptSession({
    required this.status,
    this.originalImage,
    this.currentImage,
    this.errorMessage,
  });

  const ReceiptSession.idle()
      : status = ReceiptSessionStatus.idle,
        originalImage = null,
        currentImage = null,
        errorMessage = null;

  final ReceiptSessionStatus status;
  final ReceiptImage? originalImage;
  final ReceiptImage? currentImage;
  final String? errorMessage;

  bool get hasImage => originalImage != null && currentImage != null;

  ReceiptSession copyWith({
    ReceiptSessionStatus? status,
    ReceiptImage? originalImage,
    bool clearOriginalImage = false,
    ReceiptImage? currentImage,
    bool clearCurrentImage = false,
    String? errorMessage,
    bool clearError = false,
  }) =>
      ReceiptSession(
        status: status ?? this.status,
        originalImage:
            clearOriginalImage ? null : originalImage ?? this.originalImage,
        currentImage:
            clearCurrentImage ? null : currentImage ?? this.currentImage,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      );
}

class ReceiptImageMetadata {
  const ReceiptImageMetadata({
    required this.format,
    required this.width,
    required this.height,
    required this.byteLength,
  });

  final ReceiptImageFormat format;
  final int width;
  final int height;
  final int byteLength;
}
