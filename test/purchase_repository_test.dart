import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/shared_preferences_purchase_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('purchase migration is additive and repeatable', () async {
    SharedPreferences.setMockInitialValues({'existing_user_data': 'keep-me'});
    final repository = SharedPreferencesPurchaseRepository();

    await repository.migrate();
    final prefs = await SharedPreferences.getInstance();
    final firstMigration = prefs.getString(
      SharedPreferencesPurchaseRepository.dataKey,
    );
    await repository.migrate();

    expect(
      prefs.getString(SharedPreferencesPurchaseRepository.dataKey),
      firstMigration,
    );
    expect(prefs.getString('existing_user_data'), 'keep-me');
    final decoded = jsonDecode(firstMigration!) as Map<String, dynamic>;
    expect(
      decoded['schemaVersion'],
      SharedPreferencesPurchaseRepository.schemaVersion,
    );
    expect(decoded['purchases'], isEmpty);
    expect(decoded['items'], isEmpty);
  });

  test('migrates legacy nested purchase items without data loss', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesPurchaseRepository.dataKey: jsonEncode([
        {
          ..._purchase(id: 'legacy').toJson(),
          'items': [_item(id: 'legacy-item', purchaseId: 'legacy').toJson()],
        },
      ]),
    });
    final repository = SharedPreferencesPurchaseRepository();

    await repository.migrate();

    expect((await repository.readPurchaseHistory()).single.id, 'legacy');
    expect(
      (await repository.readPurchaseDetails('legacy')).single.id,
      'legacy-item',
    );
    final prefs = await SharedPreferences.getInstance();
    final migrated = jsonDecode(
      prefs.getString(SharedPreferencesPurchaseRepository.dataKey)!,
    ) as Map<String, dynamic>;
    final migratedRaw = prefs.getString(
      SharedPreferencesPurchaseRepository.dataKey,
    );
    await repository.migrate();
    expect(
      prefs.getString(SharedPreferencesPurchaseRepository.dataKey),
      migratedRaw,
    );
    expect(
      migrated['schemaVersion'],
      SharedPreferencesPurchaseRepository.schemaVersion,
    );
    expect((migrated['items'] as List<dynamic>), hasLength(1));
    expect(
      Map<String, dynamic>.from(
        (migrated['purchases'] as List<dynamic>).single as Map,
      ).containsKey('items'),
      isFalse,
    );
  });

  test('supports purchase CRUD, history, date, store, and details', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesPurchaseRepository();
    final older = _purchase(
      id: 'older',
      storeId: 'store-a',
      date: DateTime.utc(2026, 7, 1),
    );
    final newer = _purchase(
      id: 'newer',
      storeId: 'store-b',
      date: DateTime.utc(2026, 7, 10),
    );

    await repository.createPurchase(older, [
      _item(id: 'older-item', purchaseId: older.id),
    ]);
    await repository.createPurchase(newer, [
      _item(id: 'newer-item', purchaseId: newer.id),
    ]);

    expect((await repository.readPurchaseHistory()).map((entry) => entry.id), [
      'newer',
      'older',
    ]);
    expect(
      (await repository.readPurchasesByDate(DateTime(2026, 7, 1))).single.id,
      'older',
    );
    expect(
      (await repository.readPurchasesByStore('store-b')).single.id,
      'newer',
    );
    expect(
      (await repository.readPurchaseDetails('older')).single.id,
      'older-item',
    );

    final updated = older.copyWith(notes: 'updated');
    await repository.updatePurchase(updated, [
      _item(id: 'replacement', purchaseId: older.id),
    ]);
    expect((await repository.readPurchase('older'))!.notes, 'updated');
    expect(
      (await repository.readPurchaseDetails('older')).single.id,
      'replacement',
    );

    await repository.deletePurchase('older');
    expect(await repository.readPurchase('older'), isNull);
    expect(await repository.readPurchaseDetails('older'), isEmpty);
  });

  test('store and purchase models round-trip optional data', () {
    final store = Store(
      id: 'store-a',
      name: 'Local Store',
      address: 'Main Street',
      notes: 'Open late',
      createdAt: DateTime.utc(2026, 7, 19),
    );
    final purchase = _purchase(id: 'purchase-a').copyWith(notes: 'Weekly');

    expect(Store.fromJson(store.toJson()).address, 'Main Street');
    expect(Store.fromJson(store.toJson()).notes, 'Open late');
    expect(Purchase.fromJson(purchase.toJson()).notes, 'Weekly');
  });
}

Purchase _purchase({
  required String id,
  String storeId = 'store-a',
  DateTime? date,
}) {
  final timestamp = DateTime.utc(2026, 7, 19, 10);
  return Purchase(
    id: id,
    storeId: storeId,
    purchaseDate: date ?? timestamp,
    subtotal: 10,
    discount: 0,
    tax: 0,
    total: 10,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

PurchaseItem _item({required String id, required String purchaseId}) =>
    PurchaseItem(
      id: id,
      purchaseId: purchaseId,
      productId: 'product-a',
      quantity: 1,
      unitPrice: 10,
      finalUnitPrice: 10,
      lineTotal: 10,
    );
