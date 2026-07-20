import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/app_store.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/price_history_models.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/price_history_repository.dart';
import 'package:maqadi_v2/screens/batch_management_screen.dart';
import 'package:maqadi_v2/screens/product_price_history_screen.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/price_history_service.dart';

void main() {
  testWidgets('timeline shows loading then prices newest first', (tester) async {
    final repository = _MemoryPriceHistoryRepository();
    final service = PriceHistoryService(
      repository: repository,
      clock: () => DateTime.utc(2026, 7, 20, 12),
    );
    await service.recordPurchase(
      _purchase('older', 'Old Store', DateTime.utc(2026, 7, 10)),
      [_item('older', 'older-line', 5)],
    );
    await service.recordPurchase(
      _purchase('newer', 'New Store', DateTime.utc(2026, 7, 20)),
      [_item('newer', 'newer-line', 8)],
    );

    await tester.pumpWidget(_app(_screen(service)));
    expect(
      find.byKey(const ValueKey('price-history-loading')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();

    expect(find.text('8.00 SAR'), findsOneWidget);
    expect(find.text('5.00 SAR'), findsOneWidget);
    expect(find.textContaining('New Store'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('8.00 SAR')).dy,
      lessThan(tester.getTopLeft(find.text('5.00 SAR')).dy),
    );
  });

  testWidgets('timeline shows its empty state', (tester) async {
    final service = PriceHistoryService(
      repository: _MemoryPriceHistoryRepository(),
    );

    await tester.pumpWidget(_app(_screen(service)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('price-history-empty')), findsOneWidget);
    expect(find.text('لا يوجد سجل أسعار لهذا المنتج بعد.'), findsOneWidget);
  });

  testWidgets('timeline shows repository errors and retry action', (tester) async {
    final service = PriceHistoryService(
      repository: _MemoryPriceHistoryRepository(readError: true),
    );

    await tester.pumpWidget(_app(_screen(service)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('price-history-error')), findsOneWidget);
    expect(find.textContaining('price read failed'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('product screen opens its service-backed price timeline',
      (tester) async {
    final item = PantryItem(
      id: 'rice',
      name: 'Rice',
      category: 'Food',
      minimum: 1,
      unit: 'unit',
      location: 'Pantry',
    );
    final priceService = PriceHistoryService(
      repository: _MemoryPriceHistoryRepository(),
    );
    final store = AppStore(
      inventoryService: InventoryService(items: [item]),
      priceHistoryService: priceService,
    );

    await tester.pumpWidget(
      _app(BatchManagementScreen(store: store, item: item)),
    );
    await tester.tap(
      find.byKey(const ValueKey('open-product-price-history')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('product-price-history-screen')),
      findsOneWidget,
    );
    expect(find.text('سجل أسعار Rice'), findsOneWidget);
  });
}

class _MemoryPriceHistoryRepository implements PriceHistoryRepository {
  _MemoryPriceHistoryRepository({this.readError = false});

  final bool readError;
  final List<PriceHistoryRecord> records = [];

  @override
  Future<void> applyChanges({
    List<PriceHistoryRecord> added = const [],
    Set<String> removedPurchaseItemIds = const {},
  }) async {
    records.removeWhere(
      (record) => removedPurchaseItemIds.contains(record.purchaseItemId),
    );
    records.addAll(added);
  }

  @override
  Future<List<PriceHistoryRecord>> readByProduct(String productId) async {
    if (readError) throw StateError('price read failed');
    return records.where((record) => record.productId == productId).toList();
  }

  @override
  Future<List<PriceHistoryRecord>> readByPurchase(String purchaseId) async {
    if (readError) throw StateError('price read failed');
    return records.where((record) => record.purchaseId == purchaseId).toList();
  }

  @override
  Future<void> replacePurchaseRecords(
    String purchaseId,
    List<PriceHistoryRecord> replacements,
  ) async {
    records.removeWhere((record) => record.purchaseId == purchaseId);
    records.addAll(replacements);
  }
}

Widget _screen(PriceHistoryService service) => ProductPriceHistoryScreen(
      service: service,
      productId: 'rice',
      productName: 'Rice',
    );

Widget _app(Widget home) => MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: home),
    );

Purchase _purchase(String id, String store, DateTime date) => Purchase(
      id: id,
      storeId: store,
      purchaseDate: date,
      subtotal: 0,
      discount: 0,
      tax: 0,
      total: 0,
      createdAt: date,
      updatedAt: date,
    );

PurchaseItem _item(String purchaseId, String id, double price) => PurchaseItem(
      id: id,
      purchaseId: purchaseId,
      productId: 'rice',
      quantity: 1,
      unitPrice: price,
      finalUnitPrice: price,
      lineTotal: price,
    );
