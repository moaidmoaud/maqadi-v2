import 'package:flutter/material.dart';

import '../models/dashboard_analytics_models.dart';
import '../models/inventory_models.dart';

class DashboardAnalyticsPanel extends StatefulWidget {
  const DashboardAnalyticsPanel({
    super.key,
    required this.analytics,
    required this.onSearch,
    required this.onOpenProduct,
    required this.onPantry,
    required this.onAddProduct,
    required this.onShoppingList,
    required this.onLowStock,
    required this.onOutOfStock,
    required this.onExpiringSoon,
    required this.onExpired,
    required this.onBatchManagement,
  });

  final DashboardAnalytics analytics;
  final List<DashboardSearchResult> Function(String query) onSearch;
  final ValueChanged<PantryItem> onOpenProduct;
  final VoidCallback onPantry;
  final VoidCallback onAddProduct;
  final VoidCallback onShoppingList;
  final VoidCallback onLowStock;
  final VoidCallback onOutOfStock;
  final VoidCallback onExpiringSoon;
  final VoidCallback onExpired;
  final VoidCallback onBatchManagement;

  @override
  State<DashboardAnalyticsPanel> createState() =>
      _DashboardAnalyticsPanelState();
}

class _DashboardAnalyticsPanelState extends State<DashboardAnalyticsPanel> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final query = _searchController.text.trim();
      if (query != _query) setState(() => _query = query);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analytics = widget.analytics;
    final summary = analytics.summary;
    final searchResults = widget.onSearch(_query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(
          icon: Icons.dashboard_customize_outlined,
          title: 'لوحة المخزون',
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('dashboard-global-search'),
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'بحث شامل',
            hintText: 'اسم المنتج أو التصنيف أو معرّف الدفعة',
            prefixIcon: const Icon(Icons.manage_search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close),
                  ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_query.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SearchResults(
            query: _query,
            results: searchResults,
            onOpenProduct: widget.onOpenProduct,
          ),
        ],
        const SizedBox(height: 18),
        const _SectionTitle(
          icon: Icons.assessment_outlined,
          title: 'ملخص المخزون',
        ),
        const SizedBox(height: 10),
        GridView.count(
          key: const ValueKey('dashboard-summary-grid'),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 1.55,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _SummaryCard(
              key: const ValueKey('dashboard-summary-products'),
              icon: Icons.inventory_2_outlined,
              label: 'إجمالي المنتجات',
              value: '${summary.totalProducts} منتج',
              onTap: widget.onPantry,
            ),
            _SummaryCard(
              key: const ValueKey('dashboard-summary-batches'),
              icon: Icons.layers_outlined,
              label: 'إجمالي الدفعات',
              value: '${summary.totalBatches} دفعة',
              onTap: widget.onBatchManagement,
            ),
            _SummaryCard(
              key: const ValueKey('dashboard-summary-quantity'),
              icon: Icons.scale_outlined,
              label: 'إجمالي الكمية',
              value: _formatQuantity(summary.totalQuantity),
              onTap: widget.onPantry,
            ),
            _SummaryCard(
              key: const ValueKey('dashboard-summary-low'),
              icon: Icons.warning_amber_rounded,
              label: 'مخزون منخفض',
              value: '${summary.lowStock} منتج',
              onTap: widget.onLowStock,
            ),
            _SummaryCard(
              key: const ValueKey('dashboard-summary-out'),
              icon: Icons.remove_shopping_cart_outlined,
              label: 'نفد المخزون',
              value: '${summary.outOfStock} منتج',
              onTap: widget.onOutOfStock,
            ),
            _SummaryCard(
              key: const ValueKey('dashboard-summary-expiring'),
              icon: Icons.schedule,
              label: 'قريب الانتهاء',
              value: '${summary.expiringSoon} دفعة',
              onTap: widget.onExpiringSoon,
            ),
            _SummaryCard(
              key: const ValueKey('dashboard-summary-expired'),
              icon: Icons.event_busy_outlined,
              label: 'منتهي الصلاحية',
              value: '${summary.expired} دفعة',
              onTap: widget.onExpired,
            ),
            _SummaryCard(
              key: const ValueKey('dashboard-summary-shopping'),
              icon: Icons.shopping_cart_outlined,
              label: 'عناصر قائمة التسوق',
              value: '${summary.shoppingListItems} عنصر',
              onTap: widget.onShoppingList,
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionTitle(icon: Icons.bolt_outlined, title: 'إجراءات سريعة'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ActionButton(
              key: const ValueKey('dashboard-action-add-product'),
              icon: Icons.add_box_outlined,
              label: 'إضافة منتج',
              onPressed: widget.onAddProduct,
            ),
            _ActionButton(
              icon: Icons.shopping_cart_checkout,
              label: 'قائمة التسوق',
              onPressed: widget.onShoppingList,
            ),
            _ActionButton(
              icon: Icons.schedule,
              label: 'عرض القريب',
              onPressed: widget.onExpiringSoon,
            ),
            _ActionButton(
              icon: Icons.event_busy_outlined,
              label: 'عرض المنتهي',
              onPressed: widget.onExpired,
            ),
            _ActionButton(
              key: const ValueKey('dashboard-action-batches'),
              icon: Icons.layers_outlined,
              label: 'إدارة الدفعات',
              onPressed: widget.onBatchManagement,
            ),
          ],
        ),
        const SizedBox(height: 22),
        const _SectionTitle(
          icon: Icons.donut_large_outlined,
          title: 'التوزيعات',
        ),
        const SizedBox(height: 10),
        _DistributionChart(
          key: const ValueKey('dashboard-chart-stock'),
          title: 'توزيع حالة المخزون',
          entries: analytics.stockStatusDistribution,
        ),
        const SizedBox(height: 10),
        _DistributionChart(
          key: const ValueKey('dashboard-chart-expiry'),
          title: 'توزيع حالة الصلاحية',
          entries: analytics.expiryStatusDistribution,
        ),
        const SizedBox(height: 10),
        _DistributionChart(
          key: const ValueKey('dashboard-chart-category'),
          title: 'توزيع تصنيفات المنتجات',
          entries: analytics.categoryDistribution,
        ),
        const SizedBox(height: 22),
        const _SectionTitle(
          icon: Icons.insights_outlined,
          title: 'رؤى المنتجات',
        ),
        const SizedBox(height: 10),
        _InsightSection(
          key: const ValueKey('dashboard-insight-top'),
          title: 'أعلى 10 منتجات حسب الكمية',
          items: analytics.topProducts,
          display: _InsightDisplay.quantity,
          onOpenProduct: widget.onOpenProduct,
        ),
        const SizedBox(height: 10),
        _InsightSection(
          key: const ValueKey('dashboard-insight-lowest'),
          title: 'أقل المنتجات مخزونًا',
          items: analytics.lowestStockProducts,
          display: _InsightDisplay.minimum,
          onOpenProduct: widget.onOpenProduct,
        ),
        const SizedBox(height: 10),
        _InsightSection(
          key: const ValueKey('dashboard-insight-updated'),
          title: 'المنتجات المحدثة مؤخرًا',
          items: analytics.recentlyUpdatedProducts,
          display: _InsightDisplay.updated,
          onOpenProduct: widget.onOpenProduct,
        ),
        const SizedBox(height: 10),
        _InsightSection(
          key: const ValueKey('dashboard-insight-added'),
          title: 'المنتجات المضافة مؤخرًا',
          items: analytics.recentlyAddedProducts,
          display: _InsightDisplay.added,
          onOpenProduct: widget.onOpenProduct,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22),
                const Spacer(),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w900),
                ),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.results,
    required this.onOpenProduct,
  });

  final String query;
  final List<DashboardSearchResult> results;
  final ValueChanged<PantryItem> onOpenProduct;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('لا توجد نتائج لـ "$query"'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var index = 0; index < results.length; index++) ...[
            ListTile(
              key: ValueKey('dashboard-search-${results[index].item.id}'),
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(results[index].item.name),
              subtitle: Text(_searchSubtitle(results[index])),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => onOpenProduct(results[index].item),
            ),
            if (index < results.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  String _searchSubtitle(DashboardSearchResult result) {
    final details = <String>[
      result.item.category,
      ...result.matchedFields,
      if (result.matchedBarcodes.isNotEmpty)
        'الباركود: ${result.matchedBarcodes.join('، ')}',
      if (result.matchedBatchIds.isNotEmpty)
        'الدفعات: ${result.matchedBatchIds.join('، ')}',
    ];
    return details.join(' • ');
  }
}

class _DistributionChart extends StatelessWidget {
  const _DistributionChart({
    super.key,
    required this.title,
    required this.entries,
  });

  final String title;
  final List<AnalyticsDistribution> entries;

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.value);
    final colors = [
      Theme.of(context).colorScheme.primary,
      Theme.of(context).colorScheme.tertiary,
      Theme.of(context).colorScheme.error,
      Theme.of(context).colorScheme.secondary,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Text('لا توجد بيانات')
            else
              for (var index = 0; index < entries.length; index++) ...[
                Row(
                  children: [
                    Expanded(child: Text(entries[index].label)),
                    Text('${entries[index].value}'),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : entries[index].value / total,
                  minHeight: 9,
                  borderRadius: BorderRadius.circular(20),
                  color: colors[index % colors.length],
                ),
                if (index < entries.length - 1) const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

enum _InsightDisplay { quantity, minimum, updated, added }

class _InsightSection extends StatelessWidget {
  const _InsightSection({
    super.key,
    required this.title,
    required this.items,
    required this.display,
    required this.onOpenProduct,
  });

  final String title;
  final List<ProductAnalyticsInsight> items;
  final _InsightDisplay display;
  final ValueChanged<PantryItem> onOpenProduct;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              if (items.isEmpty)
                const Text('لا توجد منتجات')
              else
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final insight = items[index];
                      return SizedBox(
                        width: 190,
                        child: Card.outlined(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => onOpenProduct(insight.item),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    insight.item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _insightSubtitle(insight),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );

  String _insightSubtitle(ProductAnalyticsInsight insight) => switch (display) {
        _InsightDisplay.quantity =>
          'الكمية: ${_formatQuantity(insight.quantity)} ${insight.item.unit}',
        _InsightDisplay.minimum =>
          'الحالي ${_formatQuantity(insight.quantity)} • الحد الأدنى ${_formatQuantity(insight.item.minimum)}',
        _InsightDisplay.updated =>
          'آخر تحديث: ${_formatDate(insight.updatedAt)}',
        _InsightDisplay.added => 'أضيف: ${_formatDate(insight.addedAt)}',
      };
}

String _formatQuantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

String _formatDate(DateTime? value) => value == null
    ? 'غير معروف'
    : '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
