import 'dart:async';

import 'package:flutter/material.dart';

import '../application/receipt_ocr_service.dart';
import '../domain/receipt_ocr_failure.dart';
import '../domain/receipt_ocr_request.dart';
import '../domain/receipt_ocr_result.dart';

enum ReceiptOcrViewStatus { loading, success, error }

class ReceiptOcrScreen extends StatefulWidget {
  const ReceiptOcrScreen({
    super.key,
    required this.service,
    required this.request,
    this.disposeService = false,
    this.onContinue,
  });

  final ReceiptOcrService service;
  final ReceiptOcrRequest request;
  final bool disposeService;
  final ValueChanged<ReceiptOcrResult>? onContinue;

  @override
  State<ReceiptOcrScreen> createState() => _ReceiptOcrScreenState();
}

class _ReceiptOcrScreenState extends State<ReceiptOcrScreen> {
  ReceiptOcrViewStatus _status = ReceiptOcrViewStatus.loading;
  ReceiptOcrResult? _result;
  String? _errorMessage;

  @override
  void dispose() {
    if (widget.disposeService) unawaited(widget.service.dispose());
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  Future<void> _recognize() async {
    setState(() {
      _status = ReceiptOcrViewStatus.loading;
      _errorMessage = null;
    });
    try {
      final result = await widget.service.recognize(widget.request);
      if (!mounted) return;
      setState(() {
        _result = result;
        _status = ReceiptOcrViewStatus.success;
      });
    } on ReceiptOcrFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _status = ReceiptOcrViewStatus.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('receipt-ocr-screen'),
        appBar: AppBar(title: const Text('التعرف على نص الإيصال')),
        body: SafeArea(
          child: switch (_status) {
            ReceiptOcrViewStatus.loading => const _OcrLoadingView(),
            ReceiptOcrViewStatus.success => _OcrResultView(
                result: _result!,
                onContinue: widget.onContinue,
              ),
            ReceiptOcrViewStatus.error => _OcrErrorView(
                message: _errorMessage!,
                onRetry: _recognize,
              ),
          },
        ),
      );
}

class _OcrLoadingView extends StatelessWidget {
  const _OcrLoadingView();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جارٍ التعرف على النص...'),
          ],
        ),
      );
}

class _OcrResultView extends StatelessWidget {
  const _OcrResultView({required this.result, this.onContinue});

  final ReceiptOcrResult result;
  final ValueChanged<ReceiptOcrResult>? onContinue;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('اكتمل التعرف على النص'),
              subtitle: Text('${result.blocks.length} كتلة نصية'),
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            result.text,
            key: const ValueKey('receipt-ocr-result-text'),
          ),
          if (onContinue != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('open-product-matching'),
              onPressed: () => onContinue!(result),
              icon: const Icon(Icons.manage_search),
              label: const Text('مطابقة المنتجات'),
            ),
          ],
          const SizedBox(height: 16),
          for (var index = 0; index < result.blocks.length; index++)
            _OcrBlockCard(index: index + 1, block: result.blocks[index]),
        ],
      );
}

class _OcrBlockCard extends StatelessWidget {
  const _OcrBlockCard({required this.index, required this.block});

  final int index;
  final ReceiptOcrBlock block;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ExpansionTile(
          title: Text('كتلة $index'),
          subtitle:
              Text(block.text, maxLines: 2, overflow: TextOverflow.ellipsis),
          children: [
            for (final line in block.lines)
              ListTile(
                title: Text(line.text),
                subtitle: Text('${line.words.length} كلمة'),
              ),
          ],
        ),
      );
}

class _OcrErrorView extends StatelessWidget {
  const _OcrErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                key: const ValueKey('receipt-ocr-error-message'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('receipt-ocr-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}
