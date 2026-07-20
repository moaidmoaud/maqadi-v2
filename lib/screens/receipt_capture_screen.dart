import 'package:flutter/material.dart';

import '../models/receipt_capture_models.dart';
import '../services/receipt_capture_service.dart';

class ReceiptCaptureScreen extends StatefulWidget {
  const ReceiptCaptureScreen({
    super.key,
    required this.service,
    this.disposeService = false,
    this.onReady,
  });

  final ReceiptCaptureService service;
  final bool disposeService;
  final ValueChanged<ReceiptImage>? onReady;

  @override
  State<ReceiptCaptureScreen> createState() => _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends State<ReceiptCaptureScreen> {
  @override
  void initState() {
    super.initState();
    widget.service.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.service.removeListener(_refresh);
    if (widget.disposeService) widget.service.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _continue() async {
    try {
      final image = await widget.service.prepareNextStep();
      if (!mounted) return;
      if (widget.onReady case final callback?) {
        callback(image);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('صورة الإيصال جاهزة للخطوة التالية.')),
        );
      }
    } catch (_) {
      // The service exposes a user-facing error through the session state.
    }
  }

  void _cancel() {
    widget.service.cancel();
    Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.service.session;
    final isProcessing = session.status == ReceiptSessionStatus.processing;
    return Scaffold(
      key: const ValueKey('receipt-capture-screen'),
      appBar: AppBar(title: const Text('التقاط إيصال')),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ReceiptSessionBanner(session: session),
                const SizedBox(height: 16),
                ReceiptPreview(image: session.currentImage),
                if (session.errorMessage case final message?) ...[
                  const SizedBox(height: 12),
                  ReceiptErrorPanel(message: message),
                ],
                const SizedBox(height: 16),
                ReceiptCaptureActions(
                  hasImage: session.hasImage,
                  enabled: !isProcessing,
                  onCamera: widget.service.captureFromCamera,
                  onGallery: widget.service.selectFromGallery,
                  onRotateLeft: widget.service.rotateLeft,
                  onRotateRight: widget.service.rotateRight,
                  onCrop: widget.service.crop,
                  onReset: widget.service.reset,
                  onNext: _continue,
                  onCancel: _cancel,
                ),
              ],
            ),
            if (isProcessing)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReceiptSessionBanner extends StatelessWidget {
  const ReceiptSessionBanner({super.key, required this.session});

  final ReceiptSession session;

  @override
  Widget build(BuildContext context) {
    final (icon, title, description) = switch (session.status) {
      ReceiptSessionStatus.idle => (
          Icons.add_a_photo_outlined,
          'اختر صورة الإيصال',
          'التقط صورة بالكاميرا أو اختر صورة من المعرض.',
        ),
      ReceiptSessionStatus.imageSelected => (
          Icons.photo_outlined,
          'تم اختيار الصورة',
          'راجع الصورة وعدّلها عند الحاجة.',
        ),
      ReceiptSessionStatus.editing => (
          Icons.edit_outlined,
          'تم تعديل الصورة',
          'يمكنك متابعة التعديل أو الانتقال للخطوة التالية.',
        ),
      ReceiptSessionStatus.ready => (
          Icons.check_circle_outline,
          'الصورة جاهزة',
          'اكتمل تجهيز صورة الإيصال.',
        ),
      ReceiptSessionStatus.processing => (
          Icons.hourglass_top,
          'جارٍ تجهيز الصورة',
          'يرجى الانتظار قليلًا.',
        ),
      ReceiptSessionStatus.error => (
          Icons.error_outline,
          'تعذر تجهيز الصورة',
          'راجع الرسالة أدناه ثم حاول مجددًا.',
        ),
      ReceiptSessionStatus.cancelled => (
          Icons.cancel_outlined,
          'تم الإلغاء',
          'لم يتم الاحتفاظ بأي صورة.',
        ),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
      ),
    );
  }
}

class ReceiptPreview extends StatelessWidget {
  const ReceiptPreview({super.key, required this.image});

  final ReceiptImage? image;

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 3 / 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: image == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64),
                      SizedBox(height: 8),
                      Text('لا توجد صورة محددة'),
                    ],
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    image!.bytes,
                    key: const ValueKey('receipt-image-preview'),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
        ),
      );
}

class ReceiptErrorPanel extends StatelessWidget {
  const ReceiptErrorPanel({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
}

class ReceiptCaptureActions extends StatelessWidget {
  const ReceiptCaptureActions({
    super.key,
    required this.hasImage,
    required this.enabled,
    required this.onCamera,
    required this.onGallery,
    required this.onRotateLeft,
    required this.onRotateRight,
    required this.onCrop,
    required this.onReset,
    required this.onNext,
    required this.onCancel,
  });

  final bool hasImage;
  final bool enabled;
  final Future<void> Function() onCamera;
  final Future<void> Function() onGallery;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;
  final Future<void> Function() onCrop;
  final VoidCallback onReset;
  final Future<void> Function() onNext;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final canEdit = enabled && hasImage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('receipt-camera'),
              onPressed: enabled ? onCamera : null,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('الكاميرا'),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('receipt-gallery'),
              onPressed: enabled ? onGallery : null,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('المعرض'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('receipt-rotate-left'),
              onPressed: canEdit ? onRotateLeft : null,
              icon: const Icon(Icons.rotate_left),
              label: const Text('تدوير يسار'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('receipt-rotate-right'),
              onPressed: canEdit ? onRotateRight : null,
              icon: const Icon(Icons.rotate_right),
              label: const Text('تدوير يمين'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('receipt-crop'),
              onPressed: canEdit ? onCrop : null,
              icon: const Icon(Icons.crop),
              label: const Text('قص'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('receipt-reset'),
              onPressed: canEdit ? onReset : null,
              icon: const Icon(Icons.restart_alt),
              label: const Text('إعادة ضبط'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('receipt-next'),
          onPressed: canEdit ? onNext : null,
          icon: const Icon(Icons.arrow_back),
          label: const Text('الخطوة التالية'),
        ),
        TextButton(
          key: const ValueKey('receipt-cancel'),
          onPressed: enabled ? onCancel : null,
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}
