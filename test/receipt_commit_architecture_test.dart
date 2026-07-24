import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Receipt Commit is isolated from receipt AI and repositories', () {
    final files = Directory('lib/receipt_commit')
        .listSync(recursive: true)
        .whereType<File>();

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('Repository')), reason: file.path);
      expect(source, isNot(contains('receipt_ocr')), reason: file.path);
      expect(source, isNot(contains('receipt_understanding')),
          reason: file.path);
      expect(source, isNot(contains('receipt_line_builder')),
          reason: file.path);
      expect(source, isNot(contains('product_matching_v2')), reason: file.path);
      expect(source, isNot(contains('receipt_benchmark')), reason: file.path);
      expect(source, isNot(contains('receipt_reliability_gate')),
          reason: file.path);
    }
  });
}
