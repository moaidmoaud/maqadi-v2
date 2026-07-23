import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extraction benchmark is read-only and independent from matching', () {
    final source = _source('lib/receipt_extraction_benchmark');
    for (final forbidden in [
      'ProductMatching',
      'product_matching',
      'Inventory',
      'Purchase',
      'Shopping',
      'Repository',
      'SharedPreferences',
      'google_mlkit',
      '.save(',
      '.delete(',
      '.update(',
      'DateTime.now',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('extraction engines and existing benchmark do not depend on diagnostics',
      () {
    for (final path in [
      'lib/receipt_ocr',
      'lib/receipt_understanding',
      'lib/receipt_line_builder',
      'lib/receipt_benchmark',
      'lib/product_matching_v2',
    ]) {
      expect(
        _source(path),
        isNot(contains('receipt_extraction_benchmark')),
        reason: path,
      );
    }
  });
}

String _source(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .map((file) => file.readAsStringSync())
    .join('\n');
