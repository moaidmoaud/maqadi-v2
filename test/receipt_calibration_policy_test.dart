import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_calibration_policy.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_line_builder_test_support.dart';

void main() {
  test('default policy preserves approved Phase 8.1 tolerances', () {
    const policy = ReceiptCalibrationPolicy();
    expect(policy.rowVerticalDistanceTolerance, 0.75);
    expect(policy.rowMinimumOverlapRatio, 0.3);
    expect(policy.columnGapTolerance, 8.0);
    expect(policy.isValid, isTrue);
  });

  test('policy values are immutable and transparent', () {
    const policy = ReceiptCalibrationPolicy();
    expect(policy.values.keys, [
      'rowVerticalDistanceTolerance',
      'rowMinimumOverlapRatio',
      'columnGapTolerance',
    ]);
    expect(
        () => policy.values['columnGapTolerance'] = 1, throwsUnsupportedError);
  });

  test('invalid normalized ratios are rejected by the engine', () {
    const engine = ReceiptLineBuilderEngine(
      policy: ReceiptCalibrationPolicy(rowMinimumOverlapRatio: 1.1),
    );
    expect(
      () => engine.build(productRow()),
      throwsA(isA<Exception>()),
    );
  });

  test('injected policy changes calibration without changing architecture', () {
    final input = [
      receiptElement('product', ReceiptElementType.productName, x: 0),
      receiptElement('price', ReceiptElementType.price, x: 150),
    ];
    final defaultResult = const ReceiptLineBuilderEngine().build(input);
    final calibratedResult = const ReceiptLineBuilderEngine(
      policy: ReceiptCalibrationPolicy(columnGapTolerance: 20),
    ).build(input);
    expect(defaultResult.lines, hasLength(2));
    expect(calibratedResult.lines, hasLength(1));
    expect(calibratedResult.lines.single.completeness,
        ReceiptLineCompleteness.complete);
  });

  test('calibration literals are centralized outside grouping code', () {
    final rules = File(
      'lib/receipt_line_builder/engine/receipt_line_grouping_rules.dart',
    ).readAsStringSync();
    final index = File(
      'lib/receipt_line_builder/engine/receipt_line_spatial_index.dart',
    ).readAsStringSync();
    expect(rules, isNot(contains('0.75')));
    expect(rules, isNot(contains('0.3')));
    expect(rules, isNot(contains('8.0')));
    expect(index, contains('ReceiptCalibrationPolicy'));
  });
}
