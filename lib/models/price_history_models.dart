class PriceHistoryRecord {
  const PriceHistoryRecord({
    required this.id,
    required this.productId,
    required this.purchaseId,
    required this.purchaseItemId,
    required this.storeId,
    required this.purchaseDate,
    required this.unitPrice,
    required this.currency,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String purchaseId;
  final String purchaseItemId;
  final String storeId;
  final DateTime purchaseDate;
  final double unitPrice;
  final String currency;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'purchaseId': purchaseId,
        'purchaseItemId': purchaseItemId,
        'storeId': storeId,
        'purchaseDate': purchaseDate.toIso8601String(),
        'unitPrice': unitPrice,
        'currency': currency,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PriceHistoryRecord.fromJson(Map<String, dynamic> json) =>
      PriceHistoryRecord(
        id: json['id'] as String? ?? '',
        productId: json['productId'] as String? ?? '',
        purchaseId: json['purchaseId'] as String? ?? '',
        purchaseItemId: json['purchaseItemId'] as String? ?? '',
        storeId: json['storeId'] as String? ?? '',
        purchaseDate: _dateFromJson(json['purchaseDate']),
        unitPrice: _doubleFromJson(json['unitPrice']),
        currency: json['currency'] as String? ?? 'SAR',
        createdAt: _dateFromJson(json['createdAt']),
      );
}

double _doubleFromJson(Object? value) => value is num ? value.toDouble() : 0;

DateTime _dateFromJson(Object? value) =>
    value is String
        ? DateTime.tryParse(value) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
