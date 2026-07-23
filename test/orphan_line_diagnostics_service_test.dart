import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/orphan_line_diagnostics/application/orphan_line_diagnostics_service.dart';
import 'package:maqadi_v2/orphan_line_diagnostics/domain/orphan_line_diagnostic.dart';
import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_completeness.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'orphan_line_diagnostics_test_support.dart';
import 'receipt_extraction_benchmark_test_support.dart';
import 'receipt_line_builder_test_support.dart';

void main() {
  const service = OrphanLineDiagnosticsService();

  test('classifies an orphan with no product element', () async {
    final elements = [
      receiptElement('price', ReceiptElementType.price),
    ];
    final result = const ReceiptLineBuilderEngine().build(elements);

    final diagnostic =
        (await service.diagnose(elements: elements, lineResult: result)).single;

    expect(diagnostic.rejectionReason, OrphanLineReason.noProductElement);
    expect(diagnostic.productElementExists, isFalse);
    expect(diagnostic.priceElementExists, isTrue);
    expect(diagnostic.recoveryPossibility, OrphanRecoveryPossibility.no);
  });

  test('classifies a row split', () async {
    final elements = [
      receiptElement(
        'product',
        ReceiptElementType.productName,
        y: 0,
      ),
      receiptElement('price', ReceiptElementType.price, y: 30),
    ];
    final result = const ReceiptLineBuilderEngine().build(elements);

    final diagnostic =
        (await service.diagnose(elements: elements, lineResult: result))
            .firstWhere((value) => value.priceElementExists);

    expect(diagnostic.rejectionReason, OrphanLineReason.failedRowGrouping);
    expect(diagnostic.sameRow, isFalse);
    expect(diagnostic.recoveryPossibility, OrphanRecoveryPossibility.maybe);
  });

  test('classifies a normalized horizontal distance split', () async {
    final elements = [
      receiptElement(
        'product',
        ReceiptElementType.productName,
        x: 0,
        width: 10,
      ),
      receiptElement(
        'price',
        ReceiptElementType.price,
        x: 100,
        width: 10,
      ),
    ];
    final result = const ReceiptLineBuilderEngine().build(elements);

    final diagnostic =
        (await service.diagnose(elements: elements, lineResult: result))
            .firstWhere((value) => value.priceElementExists);

    expect(diagnostic.rejectionReason, OrphanLineReason.distanceTooLarge);
    expect(diagnostic.sameRow, isTrue);
    expect(diagnostic.sameColumn, isFalse);
    expect(diagnostic.horizontalGap, 9);
  });

  test('classifies a role displaced by a competing candidate', () async {
    final elements = [
      receiptElement(
        'product',
        ReceiptElementType.productName,
        x: 0,
        width: 40,
      ),
      receiptElement(
        'near',
        ReceiptElementType.price,
        x: 45,
        width: 10,
      ),
      receiptElement(
        'far',
        ReceiptElementType.price,
        x: 60,
        width: 10,
      ),
    ];
    final result = const ReceiptLineBuilderEngine().build(elements);

    final diagnostic =
        (await service.diagnose(elements: elements, lineResult: result)).single;

    expect(
      diagnostic.rejectionReason,
      OrphanLineReason.multipleCompetingCandidates,
    );
    expect(diagnostic.recoveryPossibility, OrphanRecoveryPossibility.yes);
  });

  test('classifies a diagnostic orphan product without price', () async {
    final elements = [
      receiptElement('product', ReceiptElementType.productName),
    ];
    final line = extractionLine(
      id: 'orphan-product',
      productId: 'product',
      completeness: ReceiptLineCompleteness.orphan,
    );

    final diagnostic = (await service.diagnose(
      elements: elements,
      lineResult: orphanResult(line: line),
    ))
        .single;

    expect(diagnostic.rejectionReason, OrphanLineReason.noPriceElement);
    expect(diagnostic.productElementExists, isTrue);
    expect(diagnostic.priceElementExists, isFalse);
    expect(diagnostic.recoveryPossibility, OrphanRecoveryPossibility.maybe);
  });

  test('classifies a cross-column trace below the distance threshold',
      () async {
    final elements = [
      receiptElement('product', ReceiptElementType.productName, width: 40),
      receiptElement('price', ReceiptElementType.price, x: 45, width: 10),
    ];
    final line = extractionLine(
      id: 'orphan-price',
      priceId: 'price',
      completeness: ReceiptLineCompleteness.orphan,
    );

    final diagnostic = (await service.diagnose(
      elements: elements,
      lineResult: orphanResult(
        line: line,
        trace: orphanTrace(
          sourceId: 'price',
          productId: 'product',
          sourceRow: 0,
          sourceColumn: 1,
          productRow: 0,
          productColumn: 0,
        ),
      ),
    ))
        .single;

    expect(diagnostic.rejectionReason, OrphanLineReason.failedColumnGrouping);
    expect(diagnostic.horizontalGap, 0.5);
  });

  test('classifies insufficient overlap from the supplied spatial trace',
      () async {
    final elements = [
      receiptElement(
        'product',
        ReceiptElementType.productName,
        y: 0,
        height: 10,
      ),
      receiptElement(
        'price',
        ReceiptElementType.price,
        y: 7.5,
        height: 10,
      ),
    ];
    final line = extractionLine(
      id: 'orphan-price',
      priceId: 'price',
      completeness: ReceiptLineCompleteness.orphan,
    );

    final diagnostic = (await service.diagnose(
      elements: elements,
      lineResult: orphanResult(
        line: line,
        trace: orphanTrace(
          sourceId: 'price',
          productId: 'product',
          sourceRow: 1,
          sourceColumn: 0,
          productRow: 0,
          productColumn: 0,
        ),
      ),
    ))
        .single;

    expect(diagnostic.verticalDistance, 0.75);
    expect(diagnostic.verticalOverlap, 0.25);
    expect(diagnostic.rejectionReason, OrphanLineReason.overlapTooSmall);
  });

  test('classifies missing spatial trace evidence as unknown', () async {
    final elements = [
      receiptElement('product', ReceiptElementType.productName),
      receiptElement('price', ReceiptElementType.price, x: 45),
    ];
    final line = extractionLine(
      id: 'orphan-price',
      priceId: 'price',
      completeness: ReceiptLineCompleteness.orphan,
    );

    final diagnostic = (await service.diagnose(
      elements: elements,
      lineResult: orphanResult(line: line),
    ))
        .single;

    expect(diagnostic.rejectionReason, OrphanLineReason.unknown);
    expect(diagnostic.recoveryPossibility, OrphanRecoveryPossibility.no);
  });

  test('diagnostic serialization preserves evidence and recovery hint',
      () async {
    final elements = [
      receiptElement('price', ReceiptElementType.price, text: '12.50'),
    ];
    final result = const ReceiptLineBuilderEngine().build(elements);
    final diagnostic =
        (await service.diagnose(elements: elements, lineResult: result)).single;

    final restored = OrphanLineDiagnostic.fromJson(diagnostic.toJson());

    expect(restored.toJson(), diagnostic.toJson());
    expect(restored.sourceElements.single.text, '12.50');
  });

  test('recovery summary aggregates yes, maybe, and no diagnostics', () {
    final summary = OrphanRecoverySummary.fromDiagnostics([
      orphanDiagnostic(
        id: 'yes',
        recovery: OrphanRecoveryPossibility.yes,
      ),
      orphanDiagnostic(
        id: 'maybe',
        recovery: OrphanRecoveryPossibility.maybe,
      ),
      orphanDiagnostic(
        id: 'no',
        recovery: OrphanRecoveryPossibility.no,
      ),
    ]);

    expect(summary.recoverable, 1);
    expect(summary.maybeRecoverable, 1);
    expect(summary.unrecoverable, 1);
    expect(summary.total, 3);
    expect(OrphanRecoverySummary.fromJson(summary.toJson()).toJson(),
        summary.toJson());
  });
}
