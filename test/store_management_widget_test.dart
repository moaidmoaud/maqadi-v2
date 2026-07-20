import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/shared_preferences_purchase_repository.dart';
import 'package:maqadi_v2/repositories/shared_preferences_store_repository.dart';
import 'package:maqadi_v2/repositories/store_repository.dart';
import 'package:maqadi_v2/screens/store_management_screen.dart';
import 'package:maqadi_v2/services/store_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesPurchaseRepository purchases;
  late StoreService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    purchases = SharedPreferencesPurchaseRepository();
    service = StoreService(
      repository: SharedPreferencesStoreRepository(),
      purchaseRepository: purchases,
      clock: () => DateTime.utc(2026, 7, 20),
    );
  });

  testWidgets('shows loading and empty states', (tester) async {
    await tester.pumpWidget(_app(StoreManagementScreen(service: service)));
    expect(find.byKey(const ValueKey('store-loading')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('store-empty')), findsOneWidget);
  });

  testWidgets('creates and edits a store through service-backed forms',
      (tester) async {
    await tester.pumpWidget(_app(StoreManagementScreen(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-store')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('store-name')),
      'Central Market',
    );
    await tester.enterText(
      find.byKey(const ValueKey('store-branch')),
      'North',
    );
    await tester.tap(find.byKey(const ValueKey('save-store')));
    await tester.pumpAndSettle();

    expect(find.text('Central Market'), findsOneWidget);
    expect(find.text('North'), findsOneWidget);
    await tester.tap(find.text('Central Market'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('store-name')),
      'Updated Market',
    );
    await tester.tap(find.byKey(const ValueKey('save-store')));
    await tester.pumpAndSettle();

    expect(find.text('Updated Market'), findsOneWidget);
    expect(find.text('Central Market'), findsNothing);
  });

  testWidgets('searches, archives, and filters stores', (tester) async {
    final alpha = await service.createStore(name: 'Alpha Market');
    await service.createStore(name: 'Beta Shop');
    await tester.pumpWidget(_app(StoreManagementScreen(service: service)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('store-search')),
      'alpha',
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha Market'), findsOneWidget);
    expect(find.text('Beta Shop'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('store-search')), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('store-actions-${alpha.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أرشفة'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-archive-store')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha Market'), findsNothing);

    await tester.tap(find.text('مؤرشفة'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha Market'), findsOneWidget);
    expect(find.text('مؤرشف'), findsOneWidget);
  });

  testWidgets('shows a friendly message when referenced deletion is blocked',
      (tester) async {
    final store = await service.createStore(name: 'Referenced');
    await purchases.createPurchase(_purchase(store.id), []);
    await tester.pumpWidget(_app(StoreManagementScreen(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('store-actions-${store.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('حذف'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-store')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'لا يمكن حذف المتجر لوجود مشتريات مرتبطة به. يمكنك أرشفته بدلًا من ذلك.',
      ),
      findsOneWidget,
    );
    expect(find.text('Referenced'), findsOneWidget);
  });

  testWidgets('shows repository errors with a retry state', (tester) async {
    final failing = StoreService(
      repository: _FailingStoreRepository(),
      purchaseRepository: purchases,
    );
    await tester.pumpWidget(_app(StoreManagementScreen(service: failing)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('store-error')), findsOneWidget);
    expect(find.textContaining('تعذر تحميل المتاجر'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });
}

Widget _app(Widget home) => MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: home),
    );

Purchase _purchase(String storeId) => Purchase(
      id: 'purchase',
      storeId: storeId,
      purchaseDate: DateTime.utc(2026, 7, 20),
      subtotal: 0,
      discount: 0,
      tax: 0,
      total: 0,
      createdAt: DateTime.utc(2026, 7, 20),
      updatedAt: DateTime.utc(2026, 7, 20),
    );

class _FailingStoreRepository implements StoreRepository {
  @override
  Future<Store> createStore(Store store) => throw StateError('write failed');

  @override
  Future<void> deleteStore(String storeId) => throw StateError('write failed');

  @override
  Future<List<Store>> readActiveStores() => throw StateError('read failed');

  @override
  Future<List<Store>> readArchivedStores() => throw StateError('read failed');

  @override
  Future<Store?> readStore(String storeId) => throw StateError('read failed');

  @override
  Future<List<Store>> readStores() => throw StateError('read failed');

  @override
  Future<Store> updateStore(Store store) => throw StateError('write failed');
}
