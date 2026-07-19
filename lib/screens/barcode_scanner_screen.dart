import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

typedef BarcodeScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onDetected,
);

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key, this.scannerBuilder});

  final BarcodeScannerBuilder? scannerBuilder;

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _completed = false;

  void _complete(String value) {
    final clean = value.trim();
    if (_completed || clean.isEmpty || !mounted) return;
    _completed = true;
    Navigator.pop(context, clean);
  }

  Future<void> _enterManually() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إدخال الرمز يدويًا'),
        content: TextField(
          key: const ValueKey('manual-barcode-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'الباركود أو محتوى QR',
            prefixIcon: Icon(Icons.qr_code_2),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('استخدام'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) _complete(value);
  }

  @override
  Widget build(BuildContext context) {
    final scanner = widget.scannerBuilder?.call(context, _complete) ??
        MobileScanner(
          key: const ValueKey('mobile-barcode-scanner'),
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null && value.trim().isNotEmpty) {
                _complete(value);
                return;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'تعذر تشغيل الكاميرا. يمكنك إدخال الرمز يدويًا.\n${error.errorCode.name}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مسح باركود أو QR',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'إدخال يدوي',
            onPressed: _enterManually,
            icon: const Icon(Icons.keyboard_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          scanner,
          IgnorePointer(
            child: Center(
              child: Container(
                width: 280,
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 4,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'وجّه الكاميرا نحو الباركود أو رمز QR',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
