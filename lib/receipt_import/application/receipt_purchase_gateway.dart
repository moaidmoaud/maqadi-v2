import '../domain/receipt_draft.dart';

enum ReceiptPurchaseGatewayErrorCode { validation, repository, creation }

class ReceiptPurchaseGatewayException implements Exception {
  const ReceiptPurchaseGatewayException(
    this.code,
    this.message, {
    this.cause,
  });

  final ReceiptPurchaseGatewayErrorCode code;
  final String message;
  final Object? cause;
}

abstract interface class ReceiptPurchaseGateway {
  List<ReceiptDraftProductOption> receiptImportProducts();

  Future<List<ReceiptDraftStoreOption>> receiptImportStores();

  Future<ReceiptImportConfirmation> createPurchaseFromReceiptDraft(
    ReceiptDraft draft,
  );
}
