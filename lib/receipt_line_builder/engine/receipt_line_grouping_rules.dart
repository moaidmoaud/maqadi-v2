import '../../receipt_understanding/domain/receipt_element_type.dart';

class ReceiptLineGroupingRules {
  const ReceiptLineGroupingRules();

  static const excludedTypes = <ReceiptElementType>{
    ReceiptElementType.header,
    ReceiptElementType.footer,
    ReceiptElementType.metadata,
    ReceiptElementType.storeName,
    ReceiptElementType.unknown,
  };

  static const groupableTypes = <ReceiptElementType>{
    ReceiptElementType.productName,
    ReceiptElementType.quantity,
    ReceiptElementType.price,
    ReceiptElementType.total,
    ReceiptElementType.discount,
    ReceiptElementType.tax,
  };

  bool isExcluded(ReceiptElementType type) => excludedTypes.contains(type);

  bool isGroupable(ReceiptElementType type) => groupableTypes.contains(type);
}
