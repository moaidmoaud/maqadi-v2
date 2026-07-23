import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orphan diagnostics domain and service are Flutter-free and read-only',
      () {
    final source = [
      _source('lib/orphan_line_diagnostics/domain'),
      _source('lib/orphan_line_diagnostics/application'),
    ].join('\n');
    for (final forbidden in [
      'package:flutter/',
      'Repository',
      'SharedPreferences',
      'ProductMatching',
      'product_matching',
      'Inventory',
      'Purchase',
      'Shopping',
      '.save(',
      '.delete(',
      '.update(',
      'DateTime.now',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('receipt engines do not depend on orphan diagnostics', () {
    for (final path in [
      'lib/receipt_ocr',
      'lib/receipt_understanding',
      'lib/receipt_line_builder/engine',
      'lib/receipt_line_builder/domain',
      'lib/product_matching',
      'lib/product_matching_v2',
    ]) {
      expect(
        _source(path),
        isNot(contains('orphan_line_diagnostics')),
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
