import '../../product_matching/domain/product_match_models.dart';

enum ReceiptDraftConfirmationStatus {
  ready,
  confirming,
  confirmed,
  failed,
  cancelled,
}

class ReceiptDraft {
  ReceiptDraft({
    required this.id,
    required this.metadata,
    List<ReceiptDraftItem>? items,
    List<String>? unmatchedLines,
    ReceiptDraftTotals? totals,
    List<ReceiptDraftWarning>? warnings,
    this.discount = 0,
    this.tax = 0,
    this.hasUserModifications = false,
    this.confirmationStatus = ReceiptDraftConfirmationStatus.ready,
    this.confirmation,
  })  : items = items ?? <ReceiptDraftItem>[],
        unmatchedLines = unmatchedLines ?? <String>[],
        totals = totals ?? const ReceiptDraftTotals.zero(),
        warnings = warnings ?? <ReceiptDraftWarning>[];

  final String id;
  final ReceiptDraftMetadata metadata;
  final List<ReceiptDraftItem> items;
  final List<String> unmatchedLines;
  ReceiptDraftTotals totals;
  final List<ReceiptDraftWarning> warnings;
  double discount;
  double tax;
  bool hasUserModifications;
  ReceiptDraftConfirmationStatus confirmationStatus;
  ReceiptImportConfirmation? confirmation;

  bool get isCancelled =>
      confirmationStatus == ReceiptDraftConfirmationStatus.cancelled;
}

class ReceiptDraftItem {
  ReceiptDraftItem({
    required this.id,
    required this.sourceText,
    required this.quantity,
    required this.unitPrice,
    List<ReceiptDraftProductCandidate>? candidates,
    this.productId,
    this.productName,
    this.expiryDate,
  }) : candidates = candidates ?? <ReceiptDraftProductCandidate>[];

  final String id;
  final String sourceText;
  final List<ReceiptDraftProductCandidate> candidates;
  String? productId;
  String? productName;
  double quantity;
  double unitPrice;
  DateTime? expiryDate;

  double get lineTotal => quantity * unitPrice;
}

class ReceiptDraftTotals {
  const ReceiptDraftTotals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
  });

  const ReceiptDraftTotals.zero()
      : subtotal = 0,
        discount = 0,
        tax = 0,
        total = 0;

  final double subtotal;
  final double discount;
  final double tax;
  final double total;
}

enum ReceiptDraftWarningType {
  unmatchedLine,
  missingProduct,
  lowConfidence,
  zeroPrice,
}

class ReceiptDraftWarning {
  const ReceiptDraftWarning({
    required this.type,
    required this.message,
    this.itemId,
    this.sourceText,
  });

  final ReceiptDraftWarningType type;
  final String message;
  final String? itemId;
  final String? sourceText;
}

class ReceiptDraftMetadata {
  ReceiptDraftMetadata({
    required this.createdAt,
    required this.purchaseDate,
    required this.sourceLineCount,
    this.storeId,
    this.notes,
  });

  final DateTime createdAt;
  final int sourceLineCount;
  DateTime purchaseDate;
  String? storeId;
  String? notes;
}

class ReceiptDraftProductCandidate {
  const ReceiptDraftProductCandidate({
    required this.productId,
    required this.productName,
    required this.category,
    required this.confidence,
    required this.strategy,
    required this.matchedText,
  });

  final String productId;
  final String productName;
  final String category;
  final double confidence;
  final MatchingStrategyType strategy;
  final String matchedText;
}

class ReceiptDraftProductOption {
  const ReceiptDraftProductOption({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
  });

  final String id;
  final String name;
  final String category;
  final String unit;
}

class ReceiptDraftStoreOption {
  const ReceiptDraftStoreOption({required this.id, required this.name});

  final String id;
  final String name;
}

class ReceiptDraftReview {
  const ReceiptDraftReview({
    required this.draft,
    required this.products,
    required this.stores,
  });

  final ReceiptDraft draft;
  final List<ReceiptDraftProductOption> products;
  final List<ReceiptDraftStoreOption> stores;
}

class ReceiptImportConfirmation {
  const ReceiptImportConfirmation({
    required this.purchaseId,
    required this.total,
    required this.purchaseDate,
  });

  final String purchaseId;
  final double total;
  final DateTime purchaseDate;
}
