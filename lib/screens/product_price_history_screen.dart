import 'package:flutter/material.dart';

import '../models/price_history_models.dart';
import '../services/price_history_service.dart';

class ProductPriceHistoryScreen extends StatefulWidget {
  const ProductPriceHistoryScreen({
    super.key,
    required this.service,
    required this.productId,
    required this.productName,
  });

  final PriceHistoryService service;
  final String productId;
  final String productName;

  @override
  State<ProductPriceHistoryScreen> createState() =>
      _ProductPriceHistoryScreenState();
}

class _ProductPriceHistoryScreenState
    extends State<ProductPriceHistoryScreen> {
  List<PriceHistoryRecord> _records = const [];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final records =
          await widget.service.historyForProduct(widget.productId);
      if (!mounted) return;
      setState(() {
        _records = records;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        key: const ValueKey('product-price-history-screen'),
        appBar: AppBar(title: Text('سجل أسعار ${widget.productName}')),
        body: _buildBody(),
      );

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: ValueKey('price-history-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error != null) {
      return _PriceHistoryError(error: _error!, onRetry: _load);
    }
    if (_records.isEmpty) return const _PriceHistoryEmpty();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        key: const ValueKey('price-history-list'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: _records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) =>
            _PriceHistoryCard(record: _records[index]),
      ),
    );
  }
}

class _PriceHistoryCard extends StatelessWidget {
  const _PriceHistoryCard({required this.record});

  final PriceHistoryRecord record;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey('price-history-${record.id}'),
        child: ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.sell_outlined),
          ),
          title: Text(
            '${record.unitPrice.toStringAsFixed(2)} ${record.currency}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            '${record.storeId}\n${_formatDate(record.purchaseDate)}',
          ),
          isThreeLine: true,
        ),
      );
}

class _PriceHistoryEmpty extends StatelessWidget {
  const _PriceHistoryEmpty();

  @override
  Widget build(BuildContext context) => const Center(
        key: ValueKey('price-history-empty'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_outlined, size: 64),
              SizedBox(height: 12),
              Text('لا يوجد سجل أسعار لهذا المنتج بعد.'),
            ],
          ),
        ),
      );
}

class _PriceHistoryError extends StatelessWidget {
  const _PriceHistoryError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        key: const ValueKey('price-history-error'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 10),
              Text('تعذر تحميل سجل الأسعار: $error'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onRetry,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}

String _formatDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
