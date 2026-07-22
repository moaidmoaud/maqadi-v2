// These legacy UI APIs and compact control-flow statements are retained to
// avoid a visual migration during the Phase 3.1 architecture refactor.
// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';

import 'app_store.dart';
import 'consumption/presentation/consumption_screen.dart';
import 'inventory_health/presentation/inventory_health_screen.dart';
import 'low_stock/presentation/low_stock_screen.dart';
import 'models/barcode_models.dart';
import 'models/expiry_models.dart';
import 'models/inventory_models.dart';
import 'models/shopping_models.dart';
import 'models/stock_models.dart';
import 'shopping_recommendation/presentation/shopping_recommendation_screen.dart';
import 'products.dart';
import 'product_matching/domain/product_match_models.dart';
import 'product_matching/presentation/product_matching_screen.dart';
import 'product_matching/product_matching_factory.dart';
import 'receipt_ocr/application/receipt_ocr_service.dart';
import 'receipt_ocr/domain/receipt_ocr_request.dart';
import 'receipt_ocr/infrastructure/ml_kit/ml_kit_receipt_ocr_provider.dart';
import 'receipt_ocr/presentation/receipt_ocr_screen.dart';
import 'receipt_line_builder/application/receipt_line_builder_service.dart';
import 'receipt_line_builder/presentation/receipt_line_builder_debug_screen.dart';
import 'receipt_understanding/application/receipt_understanding_service.dart';
import 'receipt_understanding/presentation/receipt_understanding_debug_screen.dart';
import 'receipt_import/application/receipt_import_service.dart';
import 'receipt_import/presentation/receipt_review_screen.dart';
import 'screens/batch_management_screen.dart';
import 'screens/barcode_scanner_screen.dart';
import 'screens/expiry_list_screen.dart';
import 'screens/purchase_list_screen.dart';
import 'screens/receipt_capture_screen.dart';
import 'screens/reports_screen.dart';
import 'services/receipt_capture_service.dart';
import 'utils/arabic_text.dart';
import 'widgets/dashboard_analytics_panel.dart';
import 'widgets/notification_settings_card.dart';
import 'widgets/stock_status_badge.dart';

void main() => runApp(const MaqadiApp());

class MaqadiApp extends StatefulWidget {
  const MaqadiApp({super.key});

  @override
  State<MaqadiApp> createState() => _MaqadiAppState();
}

class _MaqadiAppState extends State<MaqadiApp> {
  final AppStore store = AppStore();

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'مقاضي',
          themeMode: store.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: const Color(0xFF2E7D32),
            scaffoldBackgroundColor: const Color(0xFFF7F8F6),
            cardTheme: const CardThemeData(margin: EdgeInsets.zero),
          ),
          darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF66BB6A),
              brightness: Brightness.dark,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(store.fontScale)),
            child: child!,
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: store.isReady
                ? HomeScreen(
                    store: store,
                    onToggleTheme: () => store.setThemeMode(
                      store.themeMode == ThemeMode.dark
                          ? ThemeMode.light
                          : ThemeMode.dark,
                    ),
                  )
                : const Scaffold(
                    body: Center(child: CircularProgressIndicator())),
          ),
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.onToggleTheme,
    this.scannerBuilder,
  });

  final AppStore store;
  final VoidCallback onToggleTheme;
  final BarcodeScannerBuilder? scannerBuilder;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool showArchived = false;

  Future<String?> _askName(BuildContext context, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(initial.isEmpty ? 'قائمة جديدة' : 'إعادة تسمية القائمة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'مثال: مقاضي البيت'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _createList() async {
    final name = await _askName(context);
    if (!mounted || name == null) return;
    final list = widget.store.createList(name);
    _openList(list);
  }

  void _openList(ShoppingListModel list, {StockStatus? initialStockFilter}) {
    widget.store.openList(list);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: ShoppingScreen(
            store: widget.store,
            list: list,
            initialStockFilter: initialStockFilter,
          ),
        ),
      ),
    );
  }

  void _openCurrentList([StockStatus? stockFilter]) {
    final list = widget.store.lastList;
    if (list == null) return;
    _openList(list, initialStockFilter: stockFilter);
  }

  void _openPantry({bool addProduct = false, String? initialBarcode}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: PantryScreen(
            store: widget.store,
            openAddProductEditor: addProduct || initialBarcode != null,
            initialBarcode: initialBarcode,
            scannerBuilder: widget.scannerBuilder,
          ),
        ),
      ),
    );
  }

  void _openExpiry(BatchExpiryStatus status) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: ExpiryListScreen(store: widget.store, status: status),
        ),
      ),
    );
  }

  void _openProduct(PantryItem item, {InventoryBatch? batch}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: BatchManagementScreen(
            store: widget.store,
            item: item,
            initialBatchId: batch?.id,
            scannerBuilder: widget.scannerBuilder,
          ),
        ),
      ),
    );
  }

  Future<void> _openBatchManagement() async {
    final items = widget.store.pantryItems();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف منتجًا إلى المخزن أولًا')),
      );
      return;
    }
    final selected = await showModalBottomSheet<PantryItem>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'اختر منتجًا لإدارة دفعاته',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            for (final item in items)
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: Text(item.name),
                subtitle: Text(item.category),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) _openProduct(selected);
  }

  Future<void> _scanInventoryCode() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute<String>(
        builder: (_) =>
            BarcodeScannerScreen(scannerBuilder: widget.scannerBuilder),
      ),
    );
    if (value == null || !mounted) return;
    final result = widget.store.resolveInventoryScan(value);
    switch (result.type) {
      case InventoryScanResultType.internalQr:
      case InventoryScanResultType.barcode:
        _openProduct(result.item!, batch: result.batch);
      case InventoryScanResultType.unknown:
        final create = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('باركود غير مسجل'),
            content: Text(
              'لم يتم العثور على منتج للرمز:\n${result.rawValue}\n\nهل تريد إنشاء منتج جديد؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('إنشاء منتج'),
              ),
            ],
          ),
        );
        if (create == true && mounted) {
          _openPantry(addProduct: true, initialBarcode: result.rawValue);
        }
    }
  }

  Future<void> _confirmDelete(ShoppingListModel list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف القائمة؟'),
        content: Text('سيتم حذف "${list.name}" نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.store.deleteList(list);
  }

  void _openSettings() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: SettingsScreen(store: widget.store),
          ),
        ),
      );

  void _openReports() => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: ReportsScreen(store: widget.store),
          ),
        ),
      );

  void _openPurchases() => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Directionality(
            textDirection: TextDirection.rtl,
            child: PurchaseListScreen(
              service: widget.store.purchaseService,
              storeService: widget.store.storeService,
            ),
          ),
        ),
      );

  void _openReceiptCapture() {
    final service = createPlatformReceiptCaptureService();
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          textDirection: TextDirection.rtl,
          child: ReceiptCaptureScreen(
            service: service,
            disposeService: true,
            onReady: (image) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Directionality(
                    textDirection: TextDirection.rtl,
                    child: ReceiptOcrScreen(
                      service: ReceiptOcrService(
                        provider: MlKitReceiptOcrProvider(),
                      ),
                      request: ReceiptOcrRequest(image: image),
                      disposeService: true,
                      onInspectStructure: (ocrResult) {
                        Navigator.push<void>(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ReceiptUnderstandingDebugScreen(
                              service: const ReceiptUnderstandingService(),
                              ocrResult: ocrResult,
                              onInspectLines: (understandingResult) {
                                Navigator.push<void>(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        ReceiptLineBuilderDebugScreen(
                                      service:
                                          const ReceiptLineBuilderService(),
                                      elements: understandingResult.elements,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                      onContinue: (ocrResult) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => Directionality(
                              textDirection: TextDirection.rtl,
                              child: ProductMatchingScreen(
                                service: createProductMatchingService(),
                                request: ProductMatchRequest(
                                  ocrResult: ocrResult,
                                ),
                                onContinue: (matchResult) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => Directionality(
                                        textDirection: TextDirection.rtl,
                                        child: ReceiptReviewScreen(
                                          service: ReceiptImportService(
                                            purchaseGateway:
                                                widget.store.purchaseService,
                                          ),
                                          ocrResult: ocrResult,
                                          matchResult: matchResult,
                                          terminateReceiptFlowOnConfirm: true,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.store.lastList;
    final analytics = widget.store.dashboardAnalytics();
    final visibleLists =
        showArchived ? widget.store.archivedLists : widget.store.activeLists;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مقاضي',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            key: const ValueKey('open-receipt-capture'),
            tooltip: 'التقاط إيصال',
            onPressed: _openReceiptCapture,
            icon: const Icon(Icons.document_scanner_outlined),
          ),
          IconButton(
            key: const ValueKey('open-purchases'),
            tooltip: 'سجل المشتريات',
            onPressed: _openPurchases,
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            key: const ValueKey('open-reports'),
            tooltip: 'التقارير والتصدير',
            onPressed: _openReports,
            icon: const Icon(Icons.file_present_outlined),
          ),
          IconButton(
            key: const ValueKey('scan-inventory-code'),
            tooltip: 'مسح باركود أو QR',
            onPressed: _scanInventoryCode,
            icon: const Icon(Icons.qr_code_scanner),
          ),
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: const Icon(Icons.dark_mode_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createList,
        icon: const Icon(Icons.add),
        label: const Text('قائمة جديدة'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          if (last != null)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openList(last),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(
                              Icons.shopping_cart_checkout,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'آخر قائمة',
                                  style: TextStyle(fontSize: 13),
                                ),
                                Text(
                                  last.name,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: last.progress,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'تم ${last.completedCount} من ${last.items.length} • المتبقي ${last.remainingCount}',
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => _openList(last),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('بدء التسوق'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _QuickCard(
                  icon: Icons.star_outline,
                  title: 'المفضلة',
                  subtitle: '${widget.store.favorites.length} منتج',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: FavoritesScreen(store: widget.store),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickCard(
                  icon: Icons.bar_chart_outlined,
                  title: 'الإحصائيات',
                  subtitle: '${widget.store.lists.length} قائمة',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Directionality(
                        textDirection: TextDirection.rtl,
                        child: StatisticsScreen(store: widget.store),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DashboardAnalyticsPanel(
            analytics: analytics,
            onSearch: widget.store.searchDashboard,
            onOpenProduct: _openProduct,
            onPantry: _openPantry,
            onAddProduct: () => _openPantry(addProduct: true),
            onShoppingList: () => _openCurrentList(),
            onLowStock: () => _openCurrentList(StockStatus.lowStock),
            onOutOfStock: () => _openCurrentList(StockStatus.outOfStock),
            onExpiringSoon: () => _openExpiry(BatchExpiryStatus.expiringSoon),
            onExpired: () => _openExpiry(BatchExpiryStatus.expired),
            onBatchManagement: _openBatchManagement,
            notificationSummary: widget.store.notificationSummary,
            onNotifications: _openSettings,
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                showArchived ? 'القوائم المؤرشفة' : 'قوائمي',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => showArchived = !showArchived),
                icon: Icon(
                  showArchived ? Icons.list_alt : Icons.archive_outlined,
                ),
                label: Text(showArchived ? 'عرض النشطة' : 'المؤرشفة'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (visibleLists.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 52),
                    SizedBox(height: 8),
                    Text('لا توجد قوائم هنا'),
                  ],
                ),
              ),
            ),
          ...visibleLists.map(
            (list) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: () => _openList(list),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(child: Text('${list.remainingCount}')),
                  title: Text(
                    list.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(
                      value: list.progress,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'rename') {
                        final name = await _askName(
                          context,
                          initial: list.name,
                        );
                        if (name != null) widget.store.renameList(list, name);
                      } else if (value == 'copy') {
                        final copy = widget.store.duplicateList(list);
                        _openList(copy);
                      } else if (value == 'archive') {
                        widget.store.archiveList(list, !list.archived);
                      } else if (value == 'delete') {
                        _confirmDelete(list);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('إعادة تسمية'),
                      ),
                      if (!list.archived)
                        const PopupMenuItem(
                          value: 'copy',
                          child: Text('نسخ القائمة'),
                        ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(list.archived ? 'إلغاء الأرشفة' : 'أرشفة'),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(height: 12),
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      );
}

class PantryScreen extends StatefulWidget {
  const PantryScreen({
    super.key,
    required this.store,
    this.openAddProductEditor = false,
    this.initialBarcode,
    this.scannerBuilder,
  });
  final AppStore store;
  final bool openAddProductEditor;
  final String? initialBarcode;
  final BarcodeScannerBuilder? scannerBuilder;

  @override
  State<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends State<PantryScreen> {
  String query = '';
  String location = 'الكل';
  bool lowOnly = false;
  String? _pendingInitialBarcode;

  Future<void> _openInventoryHealth() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => InventoryHealthScreen(
          service: widget.store.inventoryHealthService,
          onOpenProduct: (productId) async {
            final item = widget.store.pantryItemById(productId);
            if (item == null) return;
            await Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => BatchManagementScreen(
                  store: widget.store,
                  item: item,
                  scannerBuilder: widget.scannerBuilder,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openConsumption() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ConsumptionScreen(
          service: widget.store.consumptionService,
        ),
      ),
    );
  }

  Future<void> _openLowStockOutlook() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LowStockScreen(
          service: widget.store.lowStockService,
          onOpenProduct: (productId) async {
            final item = widget.store.pantryItemById(productId);
            if (item == null) return;
            await Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => BatchManagementScreen(
                  store: widget.store,
                  item: item,
                  scannerBuilder: widget.scannerBuilder,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openShoppingRecommendations() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ShoppingRecommendationScreen(
          service: widget.store.shoppingRecommendationService,
          onOpenProduct: (productId) async {
            final item = widget.store.pantryItemById(productId);
            if (item == null) return;
            await Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => BatchManagementScreen(
                  store: widget.store,
                  item: item,
                  scannerBuilder: widget.scannerBuilder,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _pendingInitialBarcode = widget.initialBarcode;
    if (widget.openAddProductEditor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showEditor();
      });
    }
  }

  Future<void> _showEditor([PantryItem? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final quantity = TextEditingController(
      text: item == null ? '1' : _format(item.quantity),
    );
    final minimum = TextEditingController(
      text: item == null ? '1' : _format(item.minimum),
    );
    final primaryBarcode = TextEditingController(
      text: item?.primaryBarcode ?? _pendingInitialBarcode ?? '',
    );
    if (item == null) _pendingInitialBarcode = null;
    String unit = item?.unit ?? 'حبة';
    String place = item?.location ?? 'المخزن';

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item == null ? 'إضافة للمخزن' : 'تعديل المنتج',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: name,
                  autofocus: item == null,
                  decoration: const InputDecoration(
                    labelText: 'اسم المنتج',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('pantry-primary-barcode-field'),
                  controller: primaryBarcode,
                  decoration: const InputDecoration(
                    labelText: 'الباركود الأساسي (اختياري)',
                    prefixIcon: Icon(Icons.qr_code_scanner),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'الكمية الحالية',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: minimum,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'الحد الأدنى',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: unit,
                  decoration: const InputDecoration(labelText: 'الوحدة'),
                  items: const [
                    'حبة',
                    'عبوة',
                    'كرتون',
                    'كجم',
                    'جرام',
                    'لتر',
                    'مل',
                    'كيس',
                    'علبة',
                  ]
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text(v)),
                      )
                      .toList(),
                  onChanged: (v) => setSheetState(() => unit = v ?? unit),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: place,
                  decoration: const InputDecoration(labelText: 'مكان التخزين'),
                  items: const [
                    'المخزن',
                    'الثلاجة',
                    'الفريزر',
                    'التنظيف',
                    'الأطفال',
                  ]
                      .map(
                        (v) => DropdownMenuItem(value: v, child: Text(v)),
                      )
                      .toList(),
                  onChanged: (v) => setSheetState(() => place = v ?? place),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != true) {
      name.dispose();
      quantity.dispose();
      minimum.dispose();
      primaryBarcode.dispose();
      return;
    }
    final q = double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0;
    final m = double.tryParse(minimum.text.replaceAll(',', '.')) ?? 0;
    try {
      if (item == null) {
        widget.store.addPantryItem(
          name: name.text,
          quantity: q,
          minimum: m,
          unit: unit,
          location: place,
          primaryBarcode: primaryBarcode.text,
        );
      } else {
        widget.store.updatePantryItem(
          item,
          name: name.text,
          quantity: q,
          minimum: m,
          unit: unit,
          location: place,
          primaryBarcode: primaryBarcode.text,
          additionalBarcodes: item.additionalBarcodes,
        );
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message?.toString() ?? 'تعذر حفظ الباركود'),
          ),
        );
      }
    }
    name.dispose();
    quantity.dispose();
    minimum.dispose();
    primaryBarcode.dispose();
  }

  String _format(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  Future<void> _addLowToList() async {
    if (widget.store.lowStockItems.isEmpty &&
        widget.store.emptyPantryItems.isEmpty) return;
    final active = widget.store.activeLists;
    ShoppingListModel? selected = widget.store.lastList;
    final result = await showDialog<ShoppingListModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة الناقص إلى قائمة'),
        content: active.isEmpty
            ? const Text(
                'لا توجد قائمة نشطة. أنشئ قائمة أولاً من الصفحة الرئيسية.',
              )
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: active
                      .map(
                        (list) => RadioListTile<ShoppingListModel>(
                          value: list,
                          groupValue: selected,
                          title: Text(list.name),
                          onChanged: (v) => Navigator.pop(context, v),
                        ),
                      )
                      .toList(),
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    if (result != null) {
      widget.store.addLowStockToList(result);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة المنتجات الناقصة إلى ${result.name}'),
          ),
        );
    }
  }

  String _dateTime(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _showHistory(PantryItem item) async {
    final movements = widget.store.movementsFor(item);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .72,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(
                  'سجل ${item.name}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text('${movements.length} حركة محفوظة'),
              ),
              const Divider(height: 1),
              Expanded(
                child: movements.isEmpty
                    ? const Center(child: Text('لا توجد حركات مسجلة بعد'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: movements.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (_, index) {
                          final movement = movements[index];
                          final sign = movement.amount > 0 ? '+' : '';
                          return ListTile(
                            leading: Icon(
                              movement.type == 'شراء'
                                  ? Icons.shopping_bag_outlined
                                  : movement.amount < 0
                                      ? Icons.remove_circle_outline
                                      : Icons.edit_outlined,
                            ),
                            title: Text(
                              movement.type,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${_dateTime(movement.createdAt)}${movement.note == null ? '' : ' • ${movement.note}'}',
                            ),
                            trailing: Text(
                              '$sign${_format(movement.amount)} ${movement.unit}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allLocations = [
      'الكل',
      ...{for (final item in widget.store.pantry) item.location},
    ];
    final items = widget.store.pantryItems(
      query: query,
      location: location == 'الكل' ? null : location,
      needsShoppingOnly: lowOnly,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'مخزن المنزل',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            key: const ValueKey('open-shopping-recommendations'),
            tooltip: 'Shopping recommendations',
            onPressed: _openShoppingRecommendations,
            icon: const Icon(Icons.recommend_outlined),
          ),
          IconButton(
            key: const ValueKey('open-low-stock-outlook'),
            tooltip: 'Low stock outlook',
            onPressed: _openLowStockOutlook,
            icon: const Icon(Icons.trending_down_outlined),
          ),
          IconButton(
            key: const ValueKey('open-consumption-history'),
            tooltip: 'Consumption history',
            onPressed: _openConsumption,
            icon: const Icon(Icons.history_outlined),
          ),
          IconButton(
            key: const ValueKey('open-inventory-health'),
            tooltip: 'Inventory health',
            onPressed: _openInventoryHealth,
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          IconButton(
            tooltip: 'إضافة الناقص للقائمة',
            onPressed: widget.store.lowStockItems.isEmpty &&
                    widget.store.emptyPantryItems.isEmpty
                ? null
                : _addLowToList,
            icon: const Icon(Icons.playlist_add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditor(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة منتج'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PantrySummary(
                        icon: Icons.inventory_2_outlined,
                        label: 'المنتجات',
                        value: '${widget.store.pantry.length}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PantrySummary(
                        icon: Icons.check_circle_outline,
                        label: 'طبيعي',
                        value: '${widget.store.healthyPantryItems.length}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _PantrySummary(
                        icon: Icons.warning_amber_rounded,
                        label: 'منخفض',
                        value: '${widget.store.lowStockItems.length}',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PantrySummary(
                        icon: Icons.remove_shopping_cart_outlined,
                        label: 'منتهي',
                        value: '${widget.store.emptyPantryItems.length}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: const InputDecoration(
                    hintText: 'ابحث في المخزن',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: allLocations.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      if (index == 0)
                        return FilterChip(
                          selected: lowOnly,
                          label: const Text('الناقص فقط'),
                          avatar: const Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                          ),
                          onSelected: (v) => setState(() => lowOnly = v),
                        );
                      final value = allLocations[index - 1];
                      return ChoiceChip(
                        selected: location == value,
                        label: Text(value),
                        onSelected: (_) => setState(() => location = value),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 68),
                        SizedBox(height: 12),
                        Text('لا توجد منتجات مطابقة'),
                        SizedBox(height: 4),
                        Text('أضف أول منتج إلى مخزن المنزل'),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      final stockInfo = widget.store.stockInfoFor(item);
                      final needsShopping =
                          stockInfo.status != StockStatus.normalStock;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _showEditor(item),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: needsShopping
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.errorContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                  child: Icon(
                                    needsShopping
                                        ? Icons.warning_amber_rounded
                                        : Icons.inventory_2_outlined,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          if (stockInfo.status ==
                                              StockStatus.outOfStock)
                                            const Text(
                                              'منتهي',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            )
                                          else if (stockInfo.status ==
                                              StockStatus.lowStock)
                                            const Text(
                                              'منخفض',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${item.location} • الحد الأدنى ${_format(item.minimum)} ${item.unit}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => widget.store
                                      .changePantryQuantity(item, -1),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Text(
                                  '${_format(item.quantity)}\n${item.unit}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => widget.store
                                      .changePantryQuantity(item, 1),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'batches') {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => BatchManagementScreen(
                                            store: widget.store,
                                            item: item,
                                            scannerBuilder:
                                                widget.scannerBuilder,
                                          ),
                                        ),
                                      );
                                    }
                                    if (v == 'edit') _showEditor(item);
                                    if (v == 'history') _showHistory(item);
                                    if (v == 'delete')
                                      widget.store.deletePantryItem(item);
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'batches',
                                      child: Text('إدارة الدفعات'),
                                    ),
                                    PopupMenuItem(
                                      value: 'history',
                                      child: Text('سجل الحركة'),
                                    ),
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('تعديل'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('حذف'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PantrySummary extends StatelessWidget {
  const _PantrySummary({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(label),
                ],
              ),
            ],
          ),
        ),
      );
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final names = store.favorites.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'المفضلة',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: names.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_border, size: 64),
                  SizedBox(height: 12),
                  Text('لا توجد منتجات مفضلة بعد'),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: names.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, index) => Card(
                child: ListTile(
                  leading: const Icon(Icons.star),
                  title: Text(
                    names[index],
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(store.categoryFor(names[index])),
                  trailing: IconButton(
                    tooltip: 'إزالة من المفضلة',
                    onPressed: () => store.toggleFavorite(names[index]),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ),
              ),
            ),
    );
  }
}

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final top = store.mostUsedProducts;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الإحصائيات',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth > 600
                  ? (constraints.maxWidth - 24) / 4
                  : (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatCard(
                    width: width,
                    icon: Icons.shopping_bag_outlined,
                    label: 'رحلات التسوق',
                    value: '${store.totalTrips}',
                  ),
                  _StatCard(
                    width: width,
                    icon: Icons.check_circle_outline,
                    label: 'أغراض مكتملة',
                    value: '${store.completedItems}',
                  ),
                  _StatCard(
                    width: width,
                    icon: Icons.list_alt,
                    label: 'إجمالي الأغراض',
                    value: '${store.totalItems}',
                  ),
                  _StatCard(
                    width: width,
                    icon: Icons.calculate_outlined,
                    label: 'متوسط الرحلة',
                    value: store.averageItemsPerTrip.toStringAsFixed(1),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'الأكثر إضافة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (top.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('ستظهر الإحصائيات بعد استخدام التطبيق'),
              ),
            ),
          for (var i = 0; i < top.length; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(
                  top[i].key,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: Text('${top[i].value} مرة'),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });
  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(height: 16),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w900),
                ),
                Text(label),
              ],
            ),
          ),
        ),
      );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text(
              'الإعدادات',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'المظهر',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.system,
                      groupValue: store.themeMode,
                      onChanged: (v) => store.setThemeMode(v!),
                      title: const Text('حسب إعداد الجهاز'),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.light,
                      groupValue: store.themeMode,
                      onChanged: (v) => store.setThemeMode(v!),
                      title: const Text('فاتح'),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      groupValue: store.themeMode,
                      onChanged: (v) => store.setThemeMode(v!),
                      title: const Text('داكن'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'حجم النص',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Slider(
                        value: store.fontScale,
                        min: 0.9,
                        max: 1.25,
                        divisions: 7,
                        label: '${(store.fontScale * 100).round()}٪',
                        onChanged: store.setFontScale,
                      ),
                      Text(
                        'نص تجريبي بحجم ${(store.fontScale * 100).round()}٪',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              NotificationSettingsCard(store: store),
              const SizedBox(height: 20),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('مقاضي Sprint 2.6 — المرحلة الثانية'),
                  subtitle: Text(
                    'ربط قائمة المقاضي بالمخزن، سجل الحركة ولوحة حالة المخزون',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({
    super.key,
    required this.store,
    required this.list,
    this.initialStockFilter,
  });

  final AppStore store;
  final ShoppingListModel list;
  final StockStatus? initialStockFilter;

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final controller = TextEditingController();
  String query = '';
  String selectedCategory = 'الكل';
  bool hideDone = false;
  bool favoritesOnly = false;
  StockStatus? stockFilter;

  List<String> get categories => [
        'الكل',
        ...{for (final product in products) product.category},
      ];

  List<Product> get suggestions {
    final normalizedQuery = normalizeArabic(query);
    final result = products.where((product) {
      final matchesCategory =
          selectedCategory == 'الكل' || product.category == selectedCategory;
      final matchesFavorite =
          !favoritesOnly || widget.store.favorites.contains(product.name);
      final searchable = normalizeArabic(
        '${product.name} ${product.aliases.join(' ')} ${product.category}',
      );
      final matchesQuery = normalizedQuery.isEmpty ||
          searchTokens(normalizedQuery).every(searchable.contains);
      return matchesCategory && matchesFavorite && matchesQuery;
    }).toList();

    result.sort((a, b) {
      if (normalizedQuery.isNotEmpty) {
        int score(Product product) {
          final name = normalizeArabic(product.name);
          if (name == normalizedQuery) return 3;
          if (name.startsWith(normalizedQuery)) return 2;
          if (name.contains(normalizedQuery)) return 1;
          return 0;
        }

        final scoreCompare = score(b).compareTo(score(a));
        if (scoreCompare != 0) return scoreCompare;
      }
      final aFavorite = widget.store.favorites.contains(a.name) ? 1 : 0;
      final bFavorite = widget.store.favorites.contains(b.name) ? 1 : 0;
      if (aFavorite != bFavorite) return bFavorite.compareTo(aFavorite);
      final aFrequency = widget.store.frequency[a.name] ?? 0;
      final bFrequency = widget.store.frequency[b.name] ?? 0;
      if (aFrequency != bFrequency) return bFrequency.compareTo(aFrequency);
      return a.name.compareTo(b.name);
    });
    return result.take(query.isEmpty ? 18 : 12).toList();
  }

  @override
  void initState() {
    super.initState();
    stockFilter = widget.initialStockFilter;
    controller.addListener(
      () => setState(() => query = controller.text.trim()),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _add(String value, [String? category]) {
    widget.store.addItems(widget.list, value, category);
    controller.clear();
  }

  Future<void> _putPurchasedInPantry() async {
    final count = widget.list.completedCount;
    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد الأغراض التي تم شراؤها أولًا')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تم وضع المقاضي في المنزل؟'),
        content: Text(
          'سيتم تحديث مخزن المنزل بـ $count غرض مشتَرى ثم حذفها من هذه القائمة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('تحديث المخزن'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final moved = widget.store.putPurchasedItemsInPantry(widget.list);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('تم تحديث المخزن بـ $moved غرض')));
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = widget.store.shoppingItemsFor(
      widget.list,
      query: query,
      stockStatus: stockFilter,
      hideDone: hideDone,
    );
    final grouped = <String, List<GroceryItem>>{};
    for (final item in visibleItems) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.list.name,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'خيارات القائمة',
            onSelected: (value) async {
              if (value == 'clearDone') {
                final count = widget.list.completedCount;
                if (count == 0) return;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('حذف المشتريات المنتهية؟'),
                    content: Text('سيتم حذف $count غرض منتهٍ.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('إلغاء'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('حذف'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) widget.store.clearCompleted(widget.list);
              }
              if (value == 'reset') widget.store.markAllPending(widget.list);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'reset',
                child: Text('إعادة كل الأغراض للمتبقي'),
              ),
              PopupMenuItem(
                value: 'clearDone',
                child: Text('حذف المشتريات المنتهية'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(controller.text),
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'تقدم التسوق',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text('${(widget.list.progress * 100).round()}٪'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: widget.list.progress),
                    duration: const Duration(milliseconds: 350),
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      minHeight: 12,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تم ${widget.list.completedCount} • المتبقي ${widget.list.remainingCount}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                widget.list.completedCount == 0 ? null : _putPurchasedInPantry,
            icon: const Icon(Icons.home_work_outlined),
            label: Text(
              widget.list.completedCount == 0
                  ? 'حدد المشتريات أولًا'
                  : 'تم وضع المقاضي في المنزل (${widget.list.completedCount})',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('shopping-search-field'),
            controller: controller,
            minLines: 1,
            maxLines: 4,
            onSubmitted: _add,
            decoration: InputDecoration(
              labelText: 'ابحث أو أضف غرضًا',
              hintText: 'مثال: حليب، بيض، خبز',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? const Icon(Icons.add_circle_outline)
                  : IconButton(
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final category = categories[index];
                return FilterChip(
                  label: Text(category),
                  selected: selectedCategory == category,
                  onSelected: (_) =>
                      setState(() => selectedCategory = category),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                avatar: const Icon(Icons.star, size: 18),
                label: const Text('المفضلة'),
                selected: favoritesOnly,
                onSelected: (value) => setState(() => favoritesOnly = value),
              ),
              FilterChip(
                avatar: const Icon(Icons.visibility_off, size: 18),
                label: const Text('إخفاء المشتريات'),
                selected: hideDone,
                onSelected: (value) => setState(() => hideDone = value),
              ),
              ChoiceChip(
                label: const Text('كل المخزون'),
                selected: stockFilter == null,
                onSelected: (_) => setState(() => stockFilter = null),
              ),
              ChoiceChip(
                label: const Text('مخزون منخفض'),
                selected: stockFilter == StockStatus.lowStock,
                onSelected: (_) =>
                    setState(() => stockFilter = StockStatus.lowStock),
              ),
              ChoiceChip(
                label: const Text('نفد المخزون'),
                selected: stockFilter == StockStatus.outOfStock,
                onSelected: (_) =>
                    setState(() => stockFilter = StockStatus.outOfStock),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'إضافة سريعة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (query.isNotEmpty && widget.store.exactProduct(query) == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                tileColor: Theme.of(context).colorScheme.secondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(Icons.add),
                title: Text('إضافة "$query"'),
                subtitle: Text(
                  'التصنيف المتوقع: ${widget.store.categoryFor(query)}',
                ),
                onTap: () => _add(query),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .map(
                  (product) => InputChip(
                    label: Text(product.name),
                    onPressed: () => _add(product.name, product.category),
                    deleteIcon: Icon(
                      widget.store.favorites.contains(product.name)
                          ? Icons.star
                          : Icons.star_border,
                      size: 18,
                    ),
                    onDeleted: () => widget.store.toggleFavorite(product.name),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          if (visibleItems.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 30),
              child: Column(
                children: [
                  const Icon(Icons.shopping_cart_outlined, size: 64),
                  const SizedBox(height: 10),
                  Text(
                    widget.list.items.isEmpty
                        ? 'القائمة فارغة'
                        : 'لا توجد عناصر مطابقة',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.list.items.isEmpty)
                    const Text('أضف أول غرض وابدأ تجهيز مقاضيك'),
                ],
              ),
            ),
          for (final entry in grouped.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    entry.key,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${entry.value.where((item) => item.done).length}/${entry.value.length}',
                  ),
                ],
              ),
            ),
            ...entry.value.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: item.done ? 0.62 : 1,
                  child: Card(
                    key: ValueKey('shopping-item-${item.id}'),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      leading: Checkbox(
                        value: item.done,
                        onChanged: (value) {
                          item.done = value ?? false;
                          widget.store.updateItem(widget.list);
                        },
                      ),
                      title: Text(
                        item.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration:
                              item.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      subtitle: _ShoppingItemSubtitle(
                        store: widget.store,
                        item: item,
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'plus') item.quantity++;
                          if (value == 'minus' && item.quantity > 1)
                            item.quantity--;
                          if (value == 'favorite')
                            widget.store.toggleFavorite(item.name);
                          if (value == 'edit') {
                            final editController = TextEditingController(
                              text: item.name,
                            );
                            final newName = await showDialog<String>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('تعديل الغرض'),
                                content: TextField(
                                  controller: editController,
                                  autofocus: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (value) =>
                                      Navigator.pop(context, value),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('إلغاء'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(
                                      context,
                                      editController.text,
                                    ),
                                    child: const Text('حفظ'),
                                  ),
                                ],
                              ),
                            );
                            if (newName != null && newName.trim().isNotEmpty) {
                              item.name = newName.trim();
                              item.category = widget.store.categoryFor(
                                item.name,
                              );
                              widget.store.updateItem(widget.list);
                            }
                          }
                          if (value == 'delete') {
                            final oldIndex = widget.list.items.indexOf(item);
                            widget.store.removeItem(widget.list, item);
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text('تم حذف ${item.name}'),
                                  action: SnackBarAction(
                                    label: 'تراجع',
                                    onPressed: () => widget.store.restoreItem(
                                      widget.list,
                                      item,
                                      oldIndex,
                                    ),
                                  ),
                                ),
                              );
                          }
                          if (value != 'favorite' && value != 'delete')
                            widget.store.updateItem(widget.list);
                        },
                        itemBuilder: (_) => [
                          if (item.pantryItemId != null)
                            const PopupMenuItem(
                              enabled: false,
                              child: Text('يُدار تلقائيًا من المخزون'),
                            ),
                          if (item.pantryItemId == null) ...[
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('تعديل الاسم'),
                            ),
                            const PopupMenuItem(
                              value: 'plus',
                              child: Text('زيادة الكمية'),
                            ),
                            const PopupMenuItem(
                              value: 'minus',
                              child: Text('تقليل الكمية'),
                            ),
                          ],
                          PopupMenuItem(
                            value: 'favorite',
                            child: Text(
                              widget.store.favorites.contains(item.name)
                                  ? 'إزالة من المفضلة'
                                  : 'إضافة للمفضلة',
                            ),
                          ),
                          if (item.pantryItemId == null)
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('حذف'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShoppingItemSubtitle extends StatelessWidget {
  const _ShoppingItemSubtitle({required this.store, required this.item});

  final AppStore store;
  final GroceryItem item;

  @override
  Widget build(BuildContext context) {
    final stockInfo = store.stockInfoForGrocery(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الكمية: ${item.quantity}'),
        if (item.pantryItemId != null) ...[
          const SizedBox(height: 4),
          const Text('أُضيف تلقائيًا من المخزون'),
        ],
        if (stockInfo != null) ...[
          const SizedBox(height: 6),
          StockStatusBadge(info: stockInfo),
        ],
      ],
    );
  }
}
