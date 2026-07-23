import 'package:maqadi_v2/receipt_line_builder/domain/receipt_line_result.dart';
import 'package:maqadi_v2/receipt_line_builder/engine/receipt_line_builder_engine.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element.dart';
import 'package:maqadi_v2/receipt_understanding/domain/receipt_element_type.dart';

import 'receipt_line_builder_test_support.dart';

class OrphanRecoveryFixture {
  const OrphanRecoveryFixture({
    required this.elements,
    required this.lineResult,
  });

  final List<ReceiptElement> elements;
  final ReceiptLineResult lineResult;
}

OrphanRecoveryFixture sameRowPriceFixture() => _fixture([
      receiptElement(
        'product',
        ReceiptElementType.productName,
        text: 'Garlic Bag',
        x: 0,
        y: 10,
        width: 20,
      ),
      receiptElement(
        'price',
        ReceiptElementType.price,
        text: '10.00',
        x: 120,
        y: 10,
        width: 20,
      ),
    ]);

OrphanRecoveryFixture sameRowQuantityFixture() => _fixture([
      receiptElement(
        'product',
        ReceiptElementType.productName,
        text: 'Garlic Bag',
        x: 0,
        y: 10,
        width: 20,
      ),
      receiptElement(
        'quantity',
        ReceiptElementType.quantity,
        text: '2',
        x: 120,
        y: 10,
        width: 20,
      ),
    ]);

OrphanRecoveryFixture sameColumnQuantityFixture() => _fixture([
      receiptElement(
        'product',
        ReceiptElementType.productName,
        text: 'Garlic Bag',
        x: 0,
        y: 10,
        width: 20,
      ),
      receiptElement(
        'quantity',
        ReceiptElementType.quantity,
        text: '2',
        x: 0,
        y: 80,
        width: 20,
      ),
    ]);

OrphanRecoveryFixture competingPriceFixture() => _fixture([
      receiptElement(
        'product',
        ReceiptElementType.productName,
        text: 'Garlic Bag',
        x: 0,
        y: 10,
        width: 20,
      ),
      receiptElement(
        'price-a',
        ReceiptElementType.price,
        text: '10.00',
        x: 120,
        y: 10,
        width: 20,
      ),
      receiptElement(
        'price-b',
        ReceiptElementType.price,
        text: '11.00',
        x: 240,
        y: 10,
        width: 20,
      ),
    ]);

OrphanRecoveryFixture ambiguousProductFixture() => _fixture([
      receiptElement(
        'product-a',
        ReceiptElementType.productName,
        text: 'Garlic Bag',
        x: 0,
        y: 10,
        width: 20,
      ),
      receiptElement(
        'product-b',
        ReceiptElementType.productName,
        text: 'Potatoes Bag',
        x: 120,
        y: 10,
        width: 20,
      ),
      receiptElement(
        'price',
        ReceiptElementType.price,
        text: '10.00',
        x: 240,
        y: 10,
        width: 20,
      ),
    ]);

OrphanRecoveryFixture priceOnlyFixture() => _fixture([
      receiptElement(
        'price',
        ReceiptElementType.price,
        text: '10.00',
        x: 120,
        y: 10,
        width: 20,
      ),
    ]);

OrphanRecoveryFixture _fixture(List<ReceiptElement> elements) =>
    OrphanRecoveryFixture(
      elements: elements,
      lineResult: const ReceiptLineBuilderEngine().build(elements),
    );
