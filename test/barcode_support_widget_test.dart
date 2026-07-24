import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/home_dashboard/application/home_dashboard_provider.dart';
import 'package:maqadi_v2/main.dart';
import 'package:maqadi_v2/screens/barcode_scanner_screen.dart';
import 'package:maqadi_v2/screens/batch_management_screen.dart';
import 'package:maqadi_v2/services/inventory_service.dart';

void main() {
  testWidgets('scanner returns the first injected camera result',
      (tester) async {
    String? scanned;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                scanned = await Navigator.push<String>(
                  context,
                  MaterialPageRoute<String>(
                    builder: (_) => BarcodeScannerScreen(
                      scannerBuilder: _fakeScanner('SCAN-123'),
                    ),
                  ),
                );
              },
              child: const Text('فتح الماسح'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح الماسح'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scanner-result')));
    await tester.pumpAndSettle();

    expect(scanned, 'SCAN-123');
  });

  testWidgets('product UI displays barcodes, generates QR, and scans another', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final inventory = InventoryService();
    final item = inventory.addStock(
      name: 'حليب',
      category: 'الألبان',
      quantity: 1,
      minimum: 1,
      unit: 'علبة',
      location: 'الثلاجة',
    );
    inventory.setBarcodes(
      item,
      primaryBarcode: 'MILK-PRIMARY',
      additionalBarcodes: ['MILK-ALT'],
    );
    final store = AppStore(inventoryService: inventory);

    await tester.pumpWidget(
      MaterialApp(
        home: BatchManagementScreen(
          store: store,
          item: item,
          scannerBuilder: _fakeScanner('MILK-NEW'),
        ),
      ),
    );

    expect(find.text('MILK-PRIMARY'), findsOneWidget);
    expect(find.text('MILK-ALT'), findsOneWidget);
    expect(find.byTooltip('نسخ الباركود'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('generate-product-qr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inventory-qr-code')), findsOneWidget);
    expect(
      find.text(store.productQrPayload(item), findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('scan-product-barcode')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scanner-result')));
    await tester.pumpAndSettle();

    expect(item.additionalBarcodes, contains('MILK-NEW'));
    expect(find.text('MILK-NEW'), findsOneWidget);
    store.dispose();
  });

  testWidgets('home scan opens known product and QR opens the target batch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final inventory = InventoryService();
    final item = inventory.addStock(
      name: 'قهوة',
      category: 'المشروبات',
      quantity: 0,
      minimum: 1,
      unit: 'كجم',
      location: 'المخزن',
    );
    final batch = inventory.addBatch(item, quantity: 2, batchId: 'COFFEE-LOT');
    inventory.setBarcodes(item, primaryBarcode: 'COFFEE-123');
    final store = AppStore(inventoryService: inventory);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          store: store,
          onToggleTheme: () {},
          scannerBuilder: _fakeScanner('COFFEE-123'),
          dashboardProvider: ExistingServicesHomeDashboardProvider(
            readAnalytics: store.dashboardAnalytics,
            readPurchaseHistory: () async => const [],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('scan-inventory-code')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scanner-result')));
    await tester.pumpAndSettle();
    expect(find.text('دفعات قهوة'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    final qrPayload = store.batchQrPayload(item, batch);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          store: store,
          onToggleTheme: () {},
          scannerBuilder: _fakeScanner(qrPayload),
          dashboardProvider: ExistingServicesHomeDashboardProvider(
            readAnalytics: store.dashboardAnalytics,
            readPurchaseHistory: () async => const [],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('scan-inventory-code')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fake-scanner-result')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('opened-batch-notice')), findsOneWidget);
    expect(find.textContaining('COFFEE-LOT'), findsWidgets);
    expect(
      find.byKey(const ValueKey('batch-card-COFFEE-LOT')),
      findsOneWidget,
    );
    store.dispose();
  });
}

BarcodeScannerBuilder _fakeScanner(String value) =>
    (context, onDetected) => Center(
          child: FilledButton(
            key: const ValueKey('fake-scanner-result'),
            onPressed: () => onDetected(value),
            child: const Text('نتيجة تجريبية'),
          ),
        );
