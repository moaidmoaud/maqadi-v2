import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine is pure and the input depends only on upstream Results', () {
    final engine =
        File('lib/low_stock/engine/low_stock_engine.dart').readAsStringSync();
    final input =
        File('lib/low_stock/domain/low_stock_input.dart').readAsStringSync();

    expect(engine, isNot(contains('package:flutter')));
    expect(engine, isNot(contains('Repository')));
    expect(engine, isNot(contains('Service')));
    expect(engine, isNot(contains('SharedPreferences')));
    expect(engine, isNot(contains('DateTime.now')));
    expect(engine, isNot(contains('.events')));
    expect(input, contains("consumption/domain/consumption_result.dart"));
    expect(input,
        contains("inventory_health/domain/inventory_health_result.dart"));
    expect(input, isNot(contains('Repository')));
    expect(input, isNot(contains('Service')));
  });

  test('feature has no persistence writes or reverse upstream dependencies',
      () {
    final files = Directory('lib/low_stock')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final source = files.map((file) => file.readAsStringSync()).join('\n');
    expect(source, isNot(contains('SharedPreferences')));
    expect(source, isNot(contains('InventoryRepository')));
    expect(source, isNot(contains('PurchaseRepository')));
    expect(source, isNot(contains('.save(')));
    expect(source, isNot(contains('.delete(')));
    expect(source, isNot(contains('.update(')));

    for (final directory in ['lib/inventory_health', 'lib/consumption']) {
      final upstream = Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(upstream, isNot(contains('low_stock')));
    }
  });
}
