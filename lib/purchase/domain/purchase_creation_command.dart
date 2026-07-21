class PurchaseCreationCommand {
  const PurchaseCreationCommand({
    required this.requestId,
    required this.storeId,
    required this.purchaseDate,
    required this.items,
    this.discount = 0,
    this.tax = 0,
    this.notes,
  });

  final String requestId;
  final String storeId;
  final DateTime purchaseDate;
  final List<PurchaseCreationItem> items;
  final double discount;
  final double tax;
  final String? notes;
}

class PurchaseCreationItem {
  const PurchaseCreationItem({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    this.expiryDate,
    this.batchId,
  });

  final String productId;
  final double quantity;
  final double unitPrice;
  final DateTime? expiryDate;
  final String? batchId;
}

class PurchaseCreationResult {
  const PurchaseCreationResult({
    required this.purchaseId,
    required this.total,
    required this.purchaseDate,
  });

  final String purchaseId;
  final double total;
  final DateTime purchaseDate;
}

enum PurchaseCreationErrorCode { validation, repository, creation }

class PurchaseCreationException implements Exception {
  const PurchaseCreationException(this.code, this.message, {this.cause});

  final PurchaseCreationErrorCode code;
  final String message;
  final Object? cause;
}
