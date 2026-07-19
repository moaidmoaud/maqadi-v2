import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/repositories/shared_preferences_app_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repository loads old JSON and round-trips additive barcode fields',
      () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesAppRepository.pantryKey: jsonEncode([
        {
          'id': 'without-barcode',
          'name': 'سكر',
          'category': 'الحبوب',
          'quantity': 2,
          'minimum': 1,
          'unit': 'كجم',
          'location': 'المخزن',
        },
        {
          'id': 'with-barcode',
          'name': 'حليب',
          'category': 'الألبان',
          'quantity': 1,
          'minimum': 1,
          'unit': 'علبة',
          'location': 'الثلاجة',
          'primaryBarcode': 'MILK-1',
          'additionalBarcodes': ['MILK-2', 'MILK-3'],
        },
      ]),
    });
    final repository = SharedPreferencesAppRepository();

    final data = await repository.load();

    expect(data.pantry.first.primaryBarcode, isNull);
    expect(data.pantry.first.quantity, 2);
    expect(data.pantry.last.primaryBarcode, 'MILK-1');
    expect(data.pantry.last.additionalBarcodes, ['MILK-2', 'MILK-3']);

    await repository.save(data);
    final preferences = await SharedPreferences.getInstance();
    final saved = jsonDecode(
      preferences.getString(SharedPreferencesAppRepository.pantryKey)!,
    ) as List<dynamic>;
    final oldProduct = Map<String, dynamic>.from(saved.first as Map);
    final barcodeProduct = Map<String, dynamic>.from(saved.last as Map);

    expect(oldProduct.containsKey('primaryBarcode'), isFalse);
    expect(oldProduct['quantity'], 2);
    expect(barcodeProduct['primaryBarcode'], 'MILK-1');
    expect(barcodeProduct['additionalBarcodes'], ['MILK-2', 'MILK-3']);
  });
}
