import 'package:flutter/material.dart';

import '../app_store.dart';
import '../models/expiry_models.dart';
import '../widgets/expiry_status_badge.dart';
import 'batch_management_screen.dart';

class ExpiryListScreen extends StatefulWidget {
  const ExpiryListScreen({super.key, required this.store, required this.status})
      : assert(status != BatchExpiryStatus.fresh);

  final AppStore store;
  final BatchExpiryStatus status;

  @override
  State<ExpiryListScreen> createState() => _ExpiryListScreenState();
}

class _ExpiryListScreenState extends State<ExpiryListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  String get _title => widget.status == BatchExpiryStatus.expiringSoon
      ? 'قريب الانتهاء'
      : 'منتهي الصلاحية';

  Future<void> _openProduct(BatchExpiryInfo info) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            BatchManagementScreen(store: widget.store, item: info.item),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.store.expiryBatches(widget.status, query: _query);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              key: const ValueKey('expiry-search-field'),
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'ابحث عن منتج أو دفعة',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'مسح البحث',
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? _ExpiryEmptyState(title: _title, hasQuery: _query.isNotEmpty)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _ExpiryBatchCard(
                      info: entries[index],
                      onTap: () => _openProduct(entries[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExpiryBatchCard extends StatelessWidget {
  const _ExpiryBatchCard({required this.info, required this.onTap});

  final BatchExpiryInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  child: Text(
                    info.item.name.isEmpty
                        ? '?'
                        : info.item.name.characters.first,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.item.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatQuantity(info.batch.quantity)} ${info.item.unit} '
                        '• ${info.item.location}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'تاريخ الانتهاء: ${_formatDate(info.batch.expiresAt!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      ExpiryStatusBadge(info: info),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left),
              ],
            ),
          ),
        ),
      );
}

class _ExpiryEmptyState extends StatelessWidget {
  const _ExpiryEmptyState({required this.title, required this.hasQuery});

  final String title;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.event_available_outlined, size: 64),
              const SizedBox(height: 12),
              Text(
                hasQuery ? 'لا توجد نتائج مطابقة' : 'لا توجد دفعات: $title',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
}

String _formatQuantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}
