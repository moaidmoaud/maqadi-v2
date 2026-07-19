import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<void> showInventoryQrDialog(
  BuildContext context, {
  required String title,
  required String payload,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColoredBox(
                color: Colors.white,
                child: SizedBox.square(
                  dimension: 230,
                  child: QrImageView(
                    key: const ValueKey('inventory-qr-code'),
                    data: payload,
                    size: 230,
                    semanticsLabel: title,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                payload,
                key: const ValueKey('inventory-qr-payload'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: payload));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم نسخ محتوى QR')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('نسخ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
