import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/repositories/shared_preferences_app_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads legacy saved data and writes the batch-aware format', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesAppRepository.listsKey: jsonEncode([
        {
          'id': 'list-1',
          'name': 'قائمتي',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-01T00:00:00.000Z',
          'items': [],
          'archived': false,
        },
      ]),
      SharedPreferencesAppRepository.favoritesKey: ['حليب'],
      SharedPreferencesAppRepository.frequencyKey: jsonEncode({'حليب': 3}),
      SharedPreferencesAppRepository.pantryKey: jsonEncode([
        {
          'id': 'pantry-1',
          'name': 'حليب',
          'category': 'الألبان والبيض',
          'quantity': 4,
          'unit': 'حبة',
          'location': 'الثلاجة',
        },
      ]),
      SharedPreferencesAppRepository.movementsKey: jsonEncode([]),
      SharedPreferencesAppRepository.lastListKey: 'list-1',
      SharedPreferencesAppRepository.themeKey: 'dark',
      SharedPreferencesAppRepository.fontScaleKey: 1.1,
    });
    final repository = SharedPreferencesAppRepository();

    final data = await repository.load();

    expect(data.lists.single.name, 'قائمتي');
    expect(data.favorites, contains('حليب'));
    expect(data.frequency['حليب'], 3);
    expect(data.pantry.single.quantity, 4);
    expect(data.pantry.single.minimum, 1);
    expect(data.pantry.single.batches, hasLength(1));
    expect(data.themeMode, 'dark');

    await repository.save(data);
    final prefs = await SharedPreferences.getInstance();
    final savedPantry =
        jsonDecode(prefs.getString(SharedPreferencesAppRepository.pantryKey)!)
            as List<dynamic>;
    final savedItem = Map<String, dynamic>.from(savedPantry.single as Map);

    expect(savedItem['quantity'], 4);
    expect(savedItem['minimum'], 1);
    expect(savedItem['batches'], hasLength(1));
    expect(
      prefs.getInt(SharedPreferencesAppRepository.schemaVersionKey),
      SharedPreferencesAppRepository.schemaVersion,
    );
  });

  test('corrupt sections do not discard valid saved sections', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesAppRepository.listsKey: 'not-json',
      SharedPreferencesAppRepository.favoritesKey: ['أرز'],
      SharedPreferencesAppRepository.frequencyKey: jsonEncode({'أرز': 2}),
      SharedPreferencesAppRepository.pantryKey: jsonEncode([]),
    });

    final data = await SharedPreferencesAppRepository().load();

    expect(data.lists, isEmpty);
    expect(data.favorites, {'أرز'});
    expect(data.frequency, {'أرز': 2});
  });

  test('round-trips batch metadata and the legacy quantity field', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesAppRepository.pantryKey: jsonEncode([
        {
          'id': 'pantry-2',
          'name': 'قهوة',
          'category': 'المشروبات',
          'quantity': 3,
          'minimum': 1,
          'unit': 'كجم',
          'location': 'المخزن',
          'batches': [
            {
              'id': 'lot-2026',
              'quantity': 3,
              'receivedAt': '2026-04-10T00:00:00.000Z',
              'expiresAt': '2027-04-10T00:00:00.000Z',
              'note': 'الدفعة الأولى',
            },
          ],
        },
      ]),
    });
    final repository = SharedPreferencesAppRepository();

    final loaded = await repository.load();
    final batch = loaded.pantry.single.batches.single;

    expect(batch.id, 'lot-2026');
    expect(batch.quantity, 3);
    expect(batch.receivedAt, DateTime.parse('2026-04-10T00:00:00.000Z'));
    expect(batch.expiresAt, DateTime.parse('2027-04-10T00:00:00.000Z'));
    expect(batch.note, 'الدفعة الأولى');

    await repository.save(loaded);
    final prefs = await SharedPreferences.getInstance();
    final savedPantry =
        jsonDecode(prefs.getString(SharedPreferencesAppRepository.pantryKey)!)
            as List<dynamic>;
    final savedItem = Map<String, dynamic>.from(savedPantry.single as Map);
    final savedBatch = Map<String, dynamic>.from(
      (savedItem['batches'] as List<dynamic>).single as Map,
    );

    expect(savedItem['quantity'], 3);
    expect(savedBatch['id'], 'lot-2026');
    expect(savedBatch['expiresAt'], '2027-04-10T00:00:00.000Z');
    expect(savedBatch['note'], 'الدفعة الأولى');
  });
}
