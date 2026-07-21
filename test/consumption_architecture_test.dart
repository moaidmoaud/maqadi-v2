import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String sourceUnder(String path) => Directory(path)
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.readAsStringSync())
      .join('\n');

  test('consumption domain and engine have no Flutter dependency', () {
    final source = '${sourceUnder('lib/consumption/domain')}\n'
        '${sourceUnder('lib/consumption/engine')}';
    expect(source, isNot(contains('package:flutter')));
  });

  test('consumption engine has no repository or service dependency', () {
    final source = sourceUnder('lib/consumption/engine');
    expect(source, isNot(contains('repositories/')));
    expect(source, isNot(contains('services/')));
    expect(source, isNot(contains('SharedPreferences')));
  });

  test('consumption feature has no forbidden feature or persistence dependency',
      () {
    final source = sourceUnder('lib/consumption');
    for (final forbidden in [
      'receipt_',
      'inventory_health',
      'shopping_models',
      'price_history',
      'notification',
      'analytics',
      'PurchaseRepository',
      'AppRepository',
      'SharedPreferences',
      'repository.save',
      'repository.update',
      'repository.delete',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
