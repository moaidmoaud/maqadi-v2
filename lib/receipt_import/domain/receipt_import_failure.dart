sealed class ReceiptImportFailure implements Exception {
  const ReceiptImportFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class InvalidReceiptDraft extends ReceiptImportFailure {
  const InvalidReceiptDraft(super.message, {super.cause});
}

class ReceiptDraftValidationFailed extends ReceiptImportFailure {
  const ReceiptDraftValidationFailed(this.errors)
      : super('يرجى تصحيح بيانات الإيصال قبل التأكيد.');

  final List<String> errors;
}

class ReceiptImportCancelled extends ReceiptImportFailure {
  const ReceiptImportCancelled([super.message = 'تم إلغاء استيراد الإيصال.']);
}

class ReceiptPurchaseCreationFailed extends ReceiptImportFailure {
  const ReceiptPurchaseCreationFailed(super.message, {super.cause});
}

class ReceiptImportRepositoryFailure extends ReceiptImportFailure {
  const ReceiptImportRepositoryFailure(super.message, {super.cause});
}
