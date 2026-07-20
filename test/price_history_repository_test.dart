import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/price_history_models.dart';
import 'package:maqadi_v2/repositories/shared_preferences_price_history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('migration is additive and repeatable for existing users', () async {
    SharedPreferences.setMockInitialValues({'existing_inventory': 'kept'});
    final repository = SharedPreferencesPriceHistoryRepository();

    await repository.migrate();
    await repository.migrate();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('existing_inventory'), 'kept');
    expect(
      preferences.getString(
        SharedPreferencesPriceHistoryRepository.dataKey,
      ),
      isNull,
    );
    expect(await repository.readByProduct('rice'), isEmpty);
  });

  test('legacy record lists migrate without changing immutable values',
      () async {
    final original = _record(id: 'legacy-price', purchaseItemId: 'legacy-line');
    SharedPreferences.setMockInitialValues({
      SharedPreferencesPriceHistoryRepository.dataKey:
          jsonEncode([original.toJson()]),
    });
    final repository = SharedPreferencesPriceHistoryRepository();

    await repository.migrate();
    final firstRaw = (await SharedPreferences.getInstance()).getString(
      SharedPreferencesPriceHistoryRepository.dataKey,
    );
    await repository.migrate();
    final secondRaw = (await SharedPreferences.getInstance()).getString(
      SharedPreferencesPriceHistoryRepository.dataKey,
    );
    final restored = (await repository.readByProduct('rice')).single;

    expect(secondRaw, firstRaw);
    expect(restored.id, original.id);
    expect(restored.purchaseId, original.purchaseId);
    expect(restored.purchaseItemId, original.purchaseItemId);
    expect(restored.storeId, original.storeId);
    expect(restored.unitPrice, original.unitPrice);
    expect(restored.currency, 'SAR');
  });

  test('applies item deltas and restores one purchase atomically', () async {
    final repository = SharedPreferencesPriceHistoryRepository();
    final rice = _record(id: 'rice-price', purchaseItemId: 'rice-line');
    final milk = _record(
      id: 'milk-price',
      productId: 'milk',
      purchaseItemId: 'milk-line',
    );
    await repository.applyChanges(added: [rice, milk]);

    final replacement = _record(
      id: 'milk-price-2',
      productId: 'milk',
      purchaseItemId: 'milk-line',
      unitPrice: 8,
    );
    await repository.applyChanges(
      added: [replacement],
      removedPurchaseItemIds: {'milk-line'},
    );

    expect((await repository.readByProduct('rice')).single.id, 'rice-price');
    expect((await repository.readByProduct('milk')).single.id, 'milk-price-2');
    await repository.replacePurchaseRecords('purchase-1', [rice]);
    expect((await repository.readByPurchase('purchase-1')).single.id,
        'rice-price');
    expect(await repository.readByProduct('milk'), isEmpty);
  });
}

PriceHistoryRecord _record({
  required String id,
  String productId = 'rice',
  String purchaseItemId = 'rice-line',
  double unitPrice = 5,
}) =>
    PriceHistoryRecord(
      id: id,
      productId: productId,
      purchaseId: 'purchase-1',
      purchaseItemId: purchaseItemId,
      storeId: 'Market',
      purchaseDate: DateTime.utc(2026, 7, 20),
      unitPrice: unitPrice,
      currency: 'SAR',
      createdAt: DateTime.utc(2026, 7, 20, 12),
    );
