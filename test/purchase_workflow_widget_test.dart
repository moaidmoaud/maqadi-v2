import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/shared_preferences_purchase_repository.dart';
import 'package:maqadi_v2/screens/purchase_details_screen.dart';
import 'package:maqadi_v2/screens/purchase_list_screen.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/purchase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late InventoryService inventory;
  late PurchaseService service;
  late PantryItem rice;
  late PantryItem milk;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rice = _pantryItem('rice', 'Rice');
    milk = _pantryItem('milk', 'Milk');
    inventory = InventoryService(items: [rice, milk]);
    service = PurchaseService(
      repository: SharedPreferencesPurchaseRepository(),
      inventoryService: inventory,
      clock: () => DateTime.utc(2026, 7, 20, 12),
    );
  });

  testWidgets('purchase list is newest first and supports search', (
    tester,
  ) async {
    await _seed(
      service,
      id: 'old',
      store: 'Alpha Market',
      date: DateTime.utc(2026, 7, 10),
      productId: rice.id,
    );
    await _seed(
      service,
      id: 'new',
      store: 'Beta Store',
      date: DateTime.utc(2026, 7, 19),
      productId: milk.id,
    );

    await tester.pumpWidget(_app(PurchaseListScreen(service: service)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('purchase-list-screen')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Beta Store')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha Market')).dy),
    );
    expect(find.textContaining('1 منتج'), findsNWidgets(2));

    await tester.enterText(
      find.byKey(const ValueKey('purchase-search')),
      'Milk',
    );
    await tester.pumpAndSettle();

    expect(find.text('Beta Store'), findsOneWidget);
    expect(find.text('Alpha Market'), findsNothing);
  });

  testWidgets('purchase details display financial and item snapshots', (
    tester,
  ) async {
    await service.createPurchase(
      id: 'purchase-1',
      storeId: 'Market',
      purchaseDate: DateTime.utc(2026, 7, 20),
      notes: 'Weekly shop',
      items: [_item('line-1', rice.id, quantity: 2, price: 10)],
      discountAmount: 5,
      taxAmount: 2,
    );

    await tester.pumpWidget(
      _app(PurchaseDetailsScreen(service: service, purchaseId: 'purchase-1')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('purchase-details-screen')),
      findsOneWidget,
    );
    expect(find.text('Market'), findsOneWidget);
    expect(find.text('Weekly shop'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('7.50 ر.س'), findsOneWidget);
    expect(find.text('15.00 ر.س'), findsOneWidget);
    expect(find.text('الدفعة المرتبطة'), findsOneWidget);
  });

  testWidgets('creates a purchase through the complete form workflow', (
    tester,
  ) async {
    await tester.pumpWidget(_app(PurchaseListScreen(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-purchase')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('purchase-store')),
      'Market',
    );
    await tester.tap(find.byKey(const ValueKey('add-purchase-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('select-product-rice')));
    await tester.pumpAndSettle();
    await tester.enterText(_textFieldWithKeyPrefix('quantity-'), '2');
    await tester.enterText(_textFieldWithKeyPrefix('unit-price-'), '10');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('purchase-discount')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('purchase-discount')),
      '5',
    );
    await tester.enterText(find.byKey(const ValueKey('purchase-tax')), '2');
    await tester.pump();

    expect(find.text('17.00 ر.س'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-purchase')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('purchase-list-screen')), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    expect(rice.quantity, 2);
    final history = await service.readPurchaseHistory();
    expect(history.single.total, 17);
  });

  testWidgets('edits a purchase using the existing linked batch', (
    tester,
  ) async {
    await _seed(
      service,
      id: 'purchase-1',
      store: 'Market',
      date: DateTime.utc(2026, 7, 20),
      productId: rice.id,
      quantity: 2,
      price: 5,
    );
    final originalBatch = rice.batches.single;
    await tester.pumpWidget(
      _app(PurchaseDetailsScreen(service: service, purchaseId: 'purchase-1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('edit-purchase')));
    await tester.pumpAndSettle();
    await tester.enterText(_textFieldWithKeyPrefix('quantity-'), '3');
    await tester.enterText(_textFieldWithKeyPrefix('unit-price-'), '6');
    await tester.tap(find.byKey(const ValueKey('save-purchase')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('purchase-details-screen')),
      findsOneWidget,
    );
    expect(rice.quantity, 3);
    expect(identical(rice.batches.single, originalBatch), isTrue);
    expect((await service.readPurchase('purchase-1'))!.subtotal, 18);
  });

  testWidgets('shows validation messages for invalid saves', (tester) async {
    await tester.pumpWidget(_app(PurchaseListScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-purchase')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-purchase')));
    await tester.pump();
    expect(find.text('يجب إضافة منتج واحد على الأقل.'), findsOneWidget);
  });

  testWidgets('shows the consumed-batch deletion rule message', (tester) async {
    await _seed(
      service,
      id: 'purchase-1',
      store: 'Market',
      date: DateTime.utc(2026, 7, 20),
      productId: rice.id,
      quantity: 2,
    );
    inventory.consume(rice, 1);
    await tester.pumpWidget(
      _app(PurchaseDetailsScreen(service: service, purchaseId: 'purchase-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-purchase')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-purchase')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text('لا يمكن حذف عملية الشراء بعد استهلاك أو تعديل إحدى دفعاتها.'),
      findsOneWidget,
    );
    expect(await service.readPurchase('purchase-1'), isNotNull);
  });
}

Widget _app(Widget home) => MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: home),
    );

Finder _textFieldWithKeyPrefix(String prefix) => find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(prefix),
    );

Future<void> _seed(
  PurchaseService service, {
  required String id,
  required String store,
  required DateTime date,
  required String productId,
  double quantity = 1,
  double price = 5,
}) =>
    service.createPurchase(
      id: id,
      storeId: store,
      purchaseDate: date,
      items: [_item('$id-line', productId, quantity: quantity, price: price)],
      discountAmount: 0,
      taxAmount: 0,
    );

PantryItem _pantryItem(String id, String name) => PantryItem(
      id: id,
      name: name,
      category: 'Food',
      minimum: 1,
      unit: 'unit',
      location: 'Pantry',
    );

PurchaseItem _item(
  String id,
  String productId, {
  required double quantity,
  required double price,
}) =>
    PurchaseItem(
      id: id,
      purchaseId: 'draft',
      productId: productId,
      quantity: quantity,
      unitPrice: price,
      finalUnitPrice: price,
      lineTotal: 0,
    );
