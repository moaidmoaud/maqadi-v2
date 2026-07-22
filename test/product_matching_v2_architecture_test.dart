import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v2 domain stays independent from OCR and application features', () {
    final source = Directory('lib/product_matching_v2/domain')
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');

    for (final forbidden in const [
      'receipt_ocr',
      'receipt_understanding',
      'inventory',
      'shopping',
      'purchase',
      'repository',
      'shared_preferences',
      'package:flutter',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('v2 service consumes ReceiptLine and does not replace v1', () {
    final v2 = File(
      'lib/product_matching_v2/application/product_matching_service_v2.dart',
    ).readAsStringSync();
    final v1 = File(
      'lib/product_matching/application/product_matching_service.dart',
    ).readAsStringSync();

    expect(v2, contains('ReceiptLine line'));
    expect(v2, isNot(contains('ReceiptOcrResult')));
    expect(v2, isNot(contains('ProductMatchingRepository')));
    expect(v1, contains('ProductMatchRequest'));
    expect(v1, contains('Future<ProductMatchResult> match'));
  });

  test('candidate generation performs no ranking or winner selection', () {
    final source = File(
      'lib/product_matching_v2/application/candidate_generation_service.dart',
    ).readAsStringSync();

    expect(source, contains('Future<List<ProductMatchCandidate>> generate'));
    expect(source, contains('candidateRanking: const []'));
    expect(source, contains('winningCandidate: null'));
    expect(source, contains("'ranking': 'notPerformed'"));
    expect(source, contains("'selection': 'notPerformed'"));
    expect(source, isNot(contains('.sort(')));
    expect(source, isNot(contains('fuzzy')));
  });
}
