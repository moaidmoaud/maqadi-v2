import 'package:flutter/material.dart';

import '../application/home_dashboard_provider.dart';
import '../domain/home_dashboard_data.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({
    super.key,
    required this.provider,
    required this.onInventory,
    required this.onShoppingList,
    required this.onLowStock,
    required this.onMonthlySavings,
    required this.onLastReceipt,
    required this.onCaptureReceipt,
    this.refreshToken,
  });

  final HomeDashboardProvider provider;
  final VoidCallback onInventory;
  final VoidCallback onShoppingList;
  final VoidCallback onLowStock;
  final VoidCallback onMonthlySavings;
  final VoidCallback onLastReceipt;
  final VoidCallback onCaptureReceipt;
  final Object? refreshToken;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  late Future<HomeDashboardData> _data;

  @override
  void initState() {
    super.initState();
    _data = widget.provider.load();
  }

  @override
  void didUpdateWidget(covariant HomeDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.provider, widget.provider) ||
        oldWidget.refreshToken != widget.refreshToken) {
      _data = widget.provider.load();
    }
  }

  Future<void> _refresh() async {
    final data = widget.provider.load();
    setState(() => _data = data);
    await data;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HomeDashboardData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _DashboardError(onRetry: _refresh);
          }
          return _DashboardContent(
            data: snapshot.requireData,
            onRefresh: _refresh,
            onInventory: widget.onInventory,
            onShoppingList: widget.onShoppingList,
            onLowStock: widget.onLowStock,
            onMonthlySavings: widget.onMonthlySavings,
            onLastReceipt: widget.onLastReceipt,
            onCaptureReceipt: widget.onCaptureReceipt,
          );
        },
      );
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.data,
    required this.onRefresh,
    required this.onInventory,
    required this.onShoppingList,
    required this.onLowStock,
    required this.onMonthlySavings,
    required this.onLastReceipt,
    required this.onCaptureReceipt,
  });

  final HomeDashboardData data;
  final RefreshCallback onRefresh;
  final VoidCallback onInventory;
  final VoidCallback onShoppingList;
  final VoidCallback onLowStock;
  final VoidCallback onMonthlySavings;
  final VoidCallback onLastReceipt;
  final VoidCallback onCaptureReceipt;

  @override
  Widget build(BuildContext context) {
    final lastReceipt = data.lastReceipt;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.count(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.05,
        children: [
          DashboardCard(
            key: const ValueKey('dashboard-inventory'),
            icon: Icons.inventory_2_outlined,
            title: 'المخزون',
            value: '${data.totalProducts}',
            detail:
                data.totalProducts == 0 ? 'لا توجد منتجات' : 'إجمالي المنتجات',
            onTap: onInventory,
          ),
          DashboardCard(
            key: const ValueKey('dashboard-shopping-list'),
            icon: Icons.shopping_cart_outlined,
            title: 'قائمة التسوق',
            value: '${data.pendingShoppingProducts}',
            detail: data.pendingShoppingProducts == 0
                ? 'لا توجد منتجات معلقة'
                : 'منتجات معلقة',
            onTap: onShoppingList,
          ),
          DashboardCard(
            key: const ValueKey('dashboard-low-stock'),
            icon: Icons.warning_amber_rounded,
            title: 'مخزون منخفض',
            value: '${data.lowStockProducts}',
            detail: data.lowStockProducts == 0
                ? 'لا توجد منتجات تحتاج انتباهًا'
                : 'منتجات تحتاج انتباهًا',
            onTap: onLowStock,
          ),
          DashboardCard(
            key: const ValueKey('dashboard-monthly-savings'),
            icon: Icons.savings_outlined,
            title: 'التوفير الشهري',
            value: data.monthlySavings == null
                ? 'قريبًا'
                : '${data.monthlySavings!.toStringAsFixed(2)} ر.س',
            detail: data.monthlySavings == null
                ? 'سيظهر ملخص التوفير هنا'
                : 'هذا الشهر',
            onTap: onMonthlySavings,
          ),
          DashboardCard(
            key: const ValueKey('dashboard-last-receipt'),
            icon: Icons.receipt_long_outlined,
            title: 'آخر إيصال',
            value: lastReceipt?.store ?? 'لا يوجد إيصال',
            detail: lastReceipt == null
                ? 'أضف أول إيصال لك'
                : '${_formatDate(lastReceipt.date)} • '
                    '${lastReceipt.productCount} منتج',
            onTap: onLastReceipt,
          ),
          DashboardCard(
            key: const ValueKey('dashboard-capture-receipt'),
            icon: Icons.document_scanner_outlined,
            title: 'التقاط إيصال',
            value: 'ابدأ الآن',
            detail: 'أضف مشترياتك من صورة الإيصال',
            emphasized: true,
            onTap: onCaptureReceipt,
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime value) =>
      '${value.year}/${value.month.toString().padLeft(2, '0')}/'
      '${value.day.toString().padLeft(2, '0')}';
}

class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: emphasized ? colors.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: emphasized ? colors.onPrimaryContainer : null),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text('تعذر تحميل ملخص المنزل'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}

class DashboardPlaceholderScreen extends StatelessWidget {
  const DashboardPlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      );
}
