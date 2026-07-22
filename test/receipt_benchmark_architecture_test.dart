import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('benchmark framework has no production persistence or business access',
      () {
    final source = _source('lib/receipt_benchmark');
    for (final forbidden in [
      'SharedPreferences',
      'Repository',
      'InventoryService',
      'PurchaseService',
      'Shopping',
      'ProductMatching',
      'google_mlkit',
      '.save(',
      '.delete(',
      '.update(',
      'DateTime.now',
      'Random(',
      'Uuid',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('ground truth fixture contains stable keys but no engine output IDs',
      () {
    final fixture =
        File('benchmark/DAN-0001/benchmark.json').readAsStringSync();
    expect(fixture, contains('fixtureKey'));
    expect(fixture, contains('synthetic-redacted-fixture-only'));
    expect(fixture, contains('"privateImageCommitted": false'));
    expect(fixture, isNot(contains('actualElementId')));
    expect(fixture, isNot(contains('ReceiptElement.id')));
  });

  test('private benchmark assets are ignored and no image is committed', () {
    final ignore = File('.gitignore').readAsStringSync();
    expect(ignore, contains('/benchmark/**/private/'));
    final images = Directory('benchmark')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => RegExp(r'\.(jpg|jpeg|png|heic)$', caseSensitive: false)
            .hasMatch(file.path));
    expect(images, isEmpty);
  });

  test('benchmark is additive and production contracts do not depend on it',
      () {
    for (final path in [
      'lib/receipt_ocr',
      'lib/receipt_understanding',
      'lib/receipt_line_builder/domain',
    ]) {
      expect(_source(path), isNot(contains('receipt_benchmark')), reason: path);
    }
  });
}

String _source(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .map((file) => file.readAsStringSync())
    .join('\n');
