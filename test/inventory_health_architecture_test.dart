import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine and domain remain Flutter and repository independent', () {
    final files = [
      ...Directory('lib/inventory_health/domain')
          .listSync(recursive: true)
          .whereType<File>(),
      ...Directory('lib/inventory_health/engine')
          .listSync(recursive: true)
          .whereType<File>(),
    ];
    final source = files.map((file) => file.readAsStringSync()).join('\n');
    expect(source, isNot(contains('package:flutter')));
    expect(source, isNot(contains('repositories/')));
    expect(source, isNot(contains('services/')));
    expect(source, isNot(contains('shared_preferences')));
  });

  test('health feature has no persistence, write, or receipt dependency', () {
    final source = Directory('lib/inventory_health')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(source, isNot(contains('SharedPreferences')));
    expect(source, isNot(contains('repository.save')));
    expect(source, isNot(contains('repository.update')));
    expect(source, isNot(contains('repository.delete')));
    expect(source, isNot(contains('receipt_')));
    expect(source, isNot(contains('purchase')));
  });
}
