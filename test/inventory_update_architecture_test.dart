import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Inventory Update Engine is pure and receipt layers remain untouched',
      () {
    final engine = File(
      'lib/inventory_update/engine/inventory_update_engine.dart',
    ).readAsStringSync();

    expect(engine, isNot(contains('package:flutter/')));
    expect(engine, isNot(contains('InventoryService')));
    expect(engine, isNot(contains('Repository')));
    expect(engine, isNot(contains('receipt_ocr')));
    expect(engine, isNot(contains('receipt_understanding')));
    expect(engine, isNot(contains('receipt_line_builder')));
    expect(engine, isNot(contains('receipt_benchmark')));
    expect(engine, isNot(contains('receipt_reliability_gate')));
  });
}
