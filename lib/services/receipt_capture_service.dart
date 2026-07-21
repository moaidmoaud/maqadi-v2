import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

import '../models/receipt_capture_models.dart';
import 'receipt_image_gateway.dart';
import 'receipt_image_validator.dart';

class ReceiptCaptureService extends ChangeNotifier {
  ReceiptCaptureService({
    required ReceiptImageAcquirer imageAcquirer,
    required ReceiptImageCropper imageCropper,
    ReceiptImageValidator validator = const ReceiptImageValidator(),
    DateTime Function()? clock,
  })  : _imageAcquirer = imageAcquirer,
        _imageCropper = imageCropper,
        _validator = validator,
        _clock = clock ?? DateTime.now;

  final ReceiptImageAcquirer _imageAcquirer;
  final ReceiptImageCropper _imageCropper;
  final ReceiptImageValidator _validator;
  final DateTime Function() _clock;

  ReceiptSession _session = const ReceiptSession.idle();
  int _operationGeneration = 0;
  bool _disposed = false;

  ReceiptSession get session => _session;

  static const Map<ReceiptSessionStatus, Set<ReceiptSessionStatus>>
      _allowedTransitions = {
    ReceiptSessionStatus.idle: {
      ReceiptSessionStatus.processing,
      ReceiptSessionStatus.error,
      ReceiptSessionStatus.cancelled,
    },
    ReceiptSessionStatus.imageSelected: {
      ReceiptSessionStatus.processing,
      ReceiptSessionStatus.editing,
      ReceiptSessionStatus.ready,
      ReceiptSessionStatus.error,
      ReceiptSessionStatus.cancelled,
    },
    ReceiptSessionStatus.editing: {
      ReceiptSessionStatus.processing,
      ReceiptSessionStatus.imageSelected,
      ReceiptSessionStatus.ready,
      ReceiptSessionStatus.error,
      ReceiptSessionStatus.cancelled,
    },
    ReceiptSessionStatus.ready: {
      ReceiptSessionStatus.processing,
      ReceiptSessionStatus.editing,
      ReceiptSessionStatus.imageSelected,
      ReceiptSessionStatus.error,
      ReceiptSessionStatus.cancelled,
    },
    ReceiptSessionStatus.processing: {
      ReceiptSessionStatus.idle,
      ReceiptSessionStatus.imageSelected,
      ReceiptSessionStatus.editing,
      ReceiptSessionStatus.ready,
      ReceiptSessionStatus.error,
      ReceiptSessionStatus.cancelled,
    },
    ReceiptSessionStatus.error: {
      ReceiptSessionStatus.processing,
      ReceiptSessionStatus.idle,
      ReceiptSessionStatus.imageSelected,
      ReceiptSessionStatus.editing,
      ReceiptSessionStatus.ready,
      ReceiptSessionStatus.cancelled,
    },
    ReceiptSessionStatus.cancelled: {
      ReceiptSessionStatus.processing,
      ReceiptSessionStatus.idle,
    },
  };

  Future<void> captureFromCamera() => _acquire(ReceiptAcquisitionSource.camera);

  Future<void> selectFromGallery() =>
      _acquire(ReceiptAcquisitionSource.gallery);

  Future<void> _acquire(ReceiptAcquisitionSource source) async {
    final operation = ++_operationGeneration;
    final previous = _session;
    _transition(
      previous.copyWith(
        status: ReceiptSessionStatus.processing,
        clearError: true,
      ),
    );
    try {
      final candidate = await _imageAcquirer.acquire(source);
      if (!_isCurrent(operation)) return;
      if (candidate == null) {
        _transition(previous);
        return;
      }
      final validated = _validator.validate(candidate, createdAt: _clock());
      _transition(
        ReceiptSession(
          status: ReceiptSessionStatus.imageSelected,
          originalImage: validated,
          currentImage: validated,
        ),
      );
    } on ReceiptCaptureException catch (error) {
      if (_isCurrent(operation)) _showError(error.message, previous);
    } catch (_) {
      if (_isCurrent(operation)) {
        _showError('تعذر الحصول على صورة الإيصال. حاول مجددًا.', previous);
      }
    }
  }

  Future<void> crop() async {
    final operation = ++_operationGeneration;
    final current = _requireImage();
    final previous = _session;
    _transition(
      previous.copyWith(
        status: ReceiptSessionStatus.processing,
        clearError: true,
      ),
    );
    try {
      final candidate = await _imageCropper.crop(current);
      if (!_isCurrent(operation)) return;
      if (candidate == null) {
        _transition(previous);
        return;
      }
      final validated = _validator.validate(candidate, createdAt: _clock());
      _transition(
        previous.copyWith(
          status: ReceiptSessionStatus.editing,
          currentImage: validated,
          clearError: true,
        ),
      );
    } on ReceiptCaptureException catch (error) {
      if (_isCurrent(operation)) _showError(error.message, previous);
    } catch (_) {
      if (_isCurrent(operation)) {
        _showError('تعذر قص صورة الإيصال. حاول مجددًا.', previous);
      }
    }
  }

  void rotateLeft() => _rotate(-90);

  void rotateRight() => _rotate(90);

  void _rotate(int angle) {
    final current = _requireImage();
    try {
      final decoded = image.decodeImage(current.bytes);
      if (decoded == null) {
        throw const ReceiptCaptureException('تعذر قراءة صورة الإيصال.');
      }
      final rotated = image.copyRotate(decoded, angle: angle);
      final validated = _validator.validate(
        ReceiptImageCandidate(
          bytes: Uint8List.fromList(image.encodePng(rotated)),
          fileName: 'edited.png',
          source: current.source,
        ),
        createdAt: _clock(),
      );
      _transition(
        _session.copyWith(
          status: ReceiptSessionStatus.editing,
          currentImage: validated,
          clearError: true,
        ),
      );
    } on ReceiptCaptureException catch (error) {
      _showError(error.message, _session);
    } catch (_) {
      _showError('تعذر تدوير صورة الإيصال. حاول مجددًا.', _session);
    }
  }

  void reset() {
    final original = _session.originalImage;
    if (original == null) return;
    _transition(
      _session.copyWith(
        status: ReceiptSessionStatus.imageSelected,
        currentImage: original,
        clearError: true,
      ),
    );
  }

  Future<ReceiptImage> prepareNextStep() async {
    final operation = ++_operationGeneration;
    final current = _requireImage();
    _transition(
      _session.copyWith(
        status: ReceiptSessionStatus.processing,
        clearError: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    if (!_isCurrent(operation)) {
      throw const ReceiptCaptureException('تم إلغاء تجهيز صورة الإيصال.');
    }
    try {
      final validated = _validator.validate(
        ReceiptImageCandidate(
          bytes: current.bytes,
          fileName: 'receipt.${current.fileExtension}',
          source: current.source,
        ),
        createdAt: current.createdAt,
      );
      _transition(
        _session.copyWith(
          status: ReceiptSessionStatus.ready,
          currentImage: validated,
          clearError: true,
        ),
      );
      return validated;
    } on ReceiptCaptureException catch (error) {
      if (_isCurrent(operation)) _showError(error.message, _session);
      rethrow;
    }
  }

  void cancel() {
    _operationGeneration++;
    _transition(const ReceiptSession(status: ReceiptSessionStatus.cancelled));
  }

  void startOver() {
    _operationGeneration++;
    _transition(const ReceiptSession.idle());
  }

  bool _isCurrent(int operation) =>
      !_disposed && operation == _operationGeneration;

  @override
  void dispose() {
    _operationGeneration++;
    _disposed = true;
    _session = const ReceiptSession(status: ReceiptSessionStatus.cancelled);
    super.dispose();
  }

  ReceiptImage _requireImage() {
    final current = _session.currentImage;
    if (current == null) {
      throw const ReceiptCaptureException('اختر صورة إيصال أولًا.');
    }
    return current;
  }

  void _showError(String message, ReceiptSession previous) {
    _transition(
      previous.copyWith(
        status: ReceiptSessionStatus.error,
        errorMessage: message,
      ),
    );
  }

  void _transition(ReceiptSession next) {
    if (next.status != _session.status &&
        !_allowedTransitions[_session.status]!.contains(next.status)) {
      throw StateError(
        'Invalid receipt session transition: '
        '${_session.status.name} -> ${next.status.name}',
      );
    }
    _session = next;
    notifyListeners();
  }
}

ReceiptCaptureService createPlatformReceiptCaptureService() =>
    ReceiptCaptureService(
      imageAcquirer: PlatformReceiptImageAcquirer(),
      imageCropper: PlatformReceiptImageCropper(),
    );
