import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/models/purchase_models.dart';
import 'package:maqadi_v2/repositories/shared_preferences_store_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('store migration is additive, repeatable, and preserves legacy fields',
      () async {
    final createdAt = DateTime.utc(2026, 7, 20);
    SharedPreferences.setMockInitialValues({
      'existing_user_data': 'keep-me',
      SharedPreferencesStoreRepository.dataKey: jsonEncode([
        {
          'id': 'legacy',
          'name': 'Legacy Store',
          'address': 'Old Branch',
          'notes': 'Keep this',
          'createdAt': createdAt.toIso8601String(),
        },
      ]),
    });
    final repository = SharedPreferencesStoreRepository();

    await repository.migrate();
    final prefs = await SharedPreferences.getInstance();
    final firstMigration = prefs.getString(
      SharedPreferencesStoreRepository.dataKey,
    );
    await repository.migrate();

    expect(
      prefs.getString(SharedPreferencesStoreRepository.dataKey),
      firstMigration,
    );
    expect(prefs.getString('existing_user_data'), 'keep-me');
    final store = (await repository.readStores()).single;
    expect(store.branch, 'Old Branch');
    expect(store.isActive, isTrue);
    expect(store.updatedAt, createdAt);
  });

  test('repository supports CRUD, lookup, filters, and default ordering',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesStoreRepository();
    final now = DateTime.utc(2026, 7, 20);
    final beta = Store(id: 'b', name: 'Beta', createdAt: now);
    final alpha = Store(id: 'a', name: 'Alpha', createdAt: now);

    await repository.createStore(beta);
    await repository.createStore(alpha);
    expect(
        (await repository.readStores()).map((store) => store.id), ['a', 'b']);
    expect((await repository.readStore('a'))!.name, 'Alpha');

    await repository.updateStore(
      alpha.copyWith(isActive: false, notes: 'Archived'),
    );
    expect((await repository.readActiveStores()).single.id, 'b');
    expect((await repository.readArchivedStores()).single.id, 'a');
    expect((await repository.readStore('a'))!.notes, 'Archived');

    await repository.deleteStore('b');
    expect(await repository.readStore('b'), isNull);
  });

  test('repository reports duplicate creates and missing updates', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesStoreRepository();
    final store = Store(
      id: 'store',
      name: 'Store',
      createdAt: DateTime.utc(2026, 7, 20),
    );
    await repository.createStore(store);

    await expectLater(repository.createStore(store), throwsStateError);
    await expectLater(
      repository.updateStore(store.copyWith(id: 'missing')),
      throwsStateError,
    );
  });
}
