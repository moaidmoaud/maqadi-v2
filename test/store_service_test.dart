import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/inventory_models.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/shared_preferences_purchase_repository.dart';
import 'package:maqadi_v2/repositories/shared_preferences_store_repository.dart';
import 'package:maqadi_v2/services/inventory_service.dart';
import 'package:maqadi_v2/services/purchase_service.dart';
import 'package:maqadi_v2/services/store_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesPurchaseRepository purchases;
  late SharedPreferencesStoreRepository stores;
  late StoreService service;
  final now = DateTime.utc(2026, 7, 20, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    purchases = SharedPreferencesPurchaseRepository();
    stores = SharedPreferencesStoreRepository();
    service = StoreService(
      repository: stores,
      purchaseRepository: purchases,
      clock: () => now,
    );
  });

  test('creates a validated immutable store with optional fields', () async {
    final store = await service.createStore(
      name: '  Central Market  ',
      branch: '  North  ',
      notes: '  Open late  ',
    );

    expect(store.name, 'Central Market');
    expect(store.branch, 'North');
    expect(store.notes, 'Open late');
    expect(store.isActive, isTrue);
    expect(store.createdAt, now);
    expect(store.updatedAt, now);
  });

  test('validates required names and duplicate active names', () async {
    await expectLater(
      service.createStore(name: '   '),
      throwsA(isA<StoreValidationException>()),
    );
    await service.createStore(name: 'Market');
    await expectLater(
      service.createStore(name: ' market '),
      throwsA(
        isA<StoreValidationException>().having(
          (error) => error.message,
          'message',
          'يوجد متجر نشط آخر بالاسم نفسه.',
        ),
      ),
    );
  });

  test('edits, archives, searches, and filters stores', () async {
    final market = await service.createStore(name: 'Market');
    await service.createStore(name: 'Bakery');
    final edited = await service.updateStore(
      storeId: market.id,
      name: 'Central Market',
      branch: 'Main',
    );
    expect(edited.name, 'Central Market');
    expect(edited.branch, 'Main');

    await service.setArchived(market.id, archived: true);
    expect((await service.activeStores()).single.name, 'Bakery');
    expect((await service.archivedStores()).single.id, market.id);
    expect(
      (await service.searchStores(
        query: 'central',
        filter: StoreStatusFilter.all,
      ))
          .single
          .id,
      market.id,
    );
  });

  test('allows a duplicate name only while the original stays archived',
      () async {
    final original = await service.createStore(name: 'Market');
    await service.setArchived(original.id, archived: true);
    await service.createStore(name: 'MARKET');

    await expectLater(
      service.setArchived(original.id, archived: false),
      throwsA(isA<StoreValidationException>()),
    );
  });

  test('deletes an unused store but blocks a referenced store', () async {
    final unused = await service.createStore(name: 'Unused');
    await service.deleteStore(unused.id);
    expect(await service.readStore(unused.id), isNull);

    final referenced = await service.createStore(name: 'Referenced');
    await purchases.createPurchase(_purchase('purchase', referenced.id), []);
    await expectLater(
      service.deleteStore(referenced.id),
      throwsA(
        isA<StoreDeletionException>().having(
          (error) => error.message,
          'message',
          contains('مشتريات مرتبطة'),
        ),
      ),
    );
    expect(await service.readStore(referenced.id), isNotNull);
  });

  test('imports legacy purchase stores once without rewriting purchases',
      () async {
    await purchases.createPurchase(_purchase('legacy', 'Legacy Market'), []);

    await service.initialize();
    await service.initialize();

    final imported = (await service.activeStores()).single;
    expect(imported.id, 'Legacy Market');
    expect(imported.name, 'Legacy Market');
    expect((await purchases.readPurchase('legacy'))!.storeId, 'Legacy Market');
  });

  test(
      'purchase integration accepts active stores and preserves archived edits',
      () async {
    final store = await service.createStore(name: 'Market');
    final rice = PantryItem(
      id: 'rice',
      name: 'Rice',
      category: 'Food',
      minimum: 1,
      unit: 'unit',
      location: 'Pantry',
    );
    final purchaseService = PurchaseService(
      repository: purchases,
      inventoryService: InventoryService(items: [rice]),
      storeService: service,
      clock: () => now,
    );
    final created = await purchaseService.createPurchase(
      id: 'purchase-1',
      storeId: store.name,
      purchaseDate: now,
      items: [_item('item-1')],
      discountAmount: 0,
      taxAmount: 0,
    );
    expect(created.storeId, store.id);

    await service.setArchived(store.id, archived: true);
    await expectLater(
      purchaseService.createPurchase(
        id: 'purchase-2',
        storeId: store.id,
        purchaseDate: now,
        items: [_item('item-2')],
        discountAmount: 0,
        taxAmount: 0,
      ),
      throwsA(isA<StoreValidationException>()),
    );

    final existingItems = await purchaseService.readPurchaseDetails(created.id);
    final updated = await purchaseService.updatePurchase(
      purchase: created.copyWith(notes: 'Historical edit'),
      items: existingItems,
      discountAmount: 0,
      taxAmount: 0,
    );
    expect(updated.storeId, store.id);
    expect(updated.notes, 'Historical edit');
    expect(
        (await purchaseService.availableStoresForPurchase(
          currentStoreId: store.id,
        ))
            .single
            .isActive,
        isFalse);
  });

  test('rejects unknown store selections when management is enabled', () async {
    final rice = PantryItem(
      id: 'rice',
      name: 'Rice',
      category: 'Food',
      minimum: 1,
      unit: 'unit',
      location: 'Pantry',
    );
    final purchaseService = PurchaseService(
      repository: purchases,
      inventoryService: InventoryService(items: [rice]),
      storeService: service,
    );

    await expectLater(
      purchaseService.createPurchase(
        id: 'purchase',
        storeId: 'Missing',
        purchaseDate: now,
        items: [_item('item')],
      ),
      throwsA(isA<StoreValidationException>()),
    );
  });
}

Purchase _purchase(String id, String storeId) => Purchase(
      id: id,
      storeId: storeId,
      purchaseDate: DateTime.utc(2026, 7, 20),
      subtotal: 0,
      discount: 0,
      tax: 0,
      total: 0,
      createdAt: DateTime.utc(2026, 7, 20),
      updatedAt: DateTime.utc(2026, 7, 20),
    );

PurchaseItem _item(String id) => PurchaseItem(
      id: id,
      purchaseId: 'draft',
      productId: 'rice',
      quantity: 1,
      unitPrice: 5,
      finalUnitPrice: 5,
      lineTotal: 5,
    );
