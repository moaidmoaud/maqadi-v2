import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine has no Flutter, repository, OCR provider, or business imports',
      () {
    final source = _source('lib/receipt_line_builder/engine');
    for (final forbidden in [
      'package:flutter',
      'google_mlkit',
      'receipt_ocr',
      'ReceiptOcrBlock',
      'ReceiptOcrProvider',
      'Repository',
      'SharedPreferences',
      'Inventory',
      'Purchase',
      'Shopping',
      'ProductMatching',
      'DateTime.now',
      'Random(',
      'Uuid',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('ReceiptElement'));
  });

  test('receipt lines contain references and never duplicate element payloads',
      () {
    final source = File('lib/receipt_line_builder/domain/receipt_line.dart')
        .readAsStringSync();
    for (final forbidden in [
      'ReceiptElement ',
      'ReceiptOcrRegion',
      ' boundingBox',
      ' confidence',
      ' text',
      'ReceiptElementType',
      'ReceiptElementEvidence',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('productElementId'));
    expect(source, contains('lineTotalElementId'));
  });

  test('feature is derived and contains no persistence or mutation boundary',
      () {
    final source = _source('lib/receipt_line_builder');
    for (final forbidden in [
      '.save(',
      '.delete(',
      '.update(',
      'Repository',
      'SharedPreferences',
      'sqflite',
      'cloud',
      'AIService',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('UI delegates grouping and does not calculate completeness or metrics',
      () {
    final source = _source('lib/receipt_line_builder/presentation');
    expect(source, contains('ReceiptLineBuilderService'));
    for (final forbidden in [
      'medianPositiveHeight',
      'normalizedVerticalDistance(',
      'ReceiptLineCompleteness.complete :',
      'ReceiptLineBuilderEngine(',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}

String _source(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .map((file) => file.readAsStringSync())
    .join('\n');
