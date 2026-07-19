class Store {
  const Store({
    required this.id,
    required this.name,
    required this.createdAt,
    this.address,
    this.notes,
  });

  final String id;
  final String name;
  final String? address;
  final String? notes;
  final DateTime createdAt;

  Store copyWith({
    String? id,
    String? name,
    String? address,
    bool clearAddress = false,
    String? notes,
    bool clearNotes = false,
    DateTime? createdAt,
  }) =>
      Store(
        id: id ?? this.id,
        name: name ?? this.name,
        address: clearAddress ? null : address ?? this.address,
        notes: clearNotes ? null : notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (address != null) 'address': address,
        if (notes != null) 'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Store.fromJson(Map<String, dynamic> json) => Store(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        address: json['address'] as String?,
        notes: json['notes'] as String?,
        createdAt: _dateFromJson(json['createdAt']),
      );
}

class Purchase {
  const Purchase({
    required this.id,
    required this.storeId,
    required this.purchaseDate,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
  });

  final String id;
  final String storeId;
  final DateTime purchaseDate;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Purchase copyWith({
    String? id,
    String? storeId,
    DateTime? purchaseDate,
    double? subtotal,
    double? discount,
    double? tax,
    double? total,
    String? notes,
    bool clearNotes = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Purchase(
        id: id ?? this.id,
        storeId: storeId ?? this.storeId,
        purchaseDate: purchaseDate ?? this.purchaseDate,
        subtotal: subtotal ?? this.subtotal,
        discount: discount ?? this.discount,
        tax: tax ?? this.tax,
        total: total ?? this.total,
        notes: clearNotes ? null : notes ?? this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'storeId': storeId,
        'purchaseDate': purchaseDate.toIso8601String(),
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'total': total,
        if (notes != null) 'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
        id: json['id'] as String? ?? '',
        storeId: json['storeId'] as String? ?? '',
        purchaseDate: _dateFromJson(json['purchaseDate']),
        subtotal: _doubleFromJson(json['subtotal']),
        discount: _doubleFromJson(json['discount']),
        tax: _doubleFromJson(json['tax']),
        total: _doubleFromJson(json['total']),
        notes: json['notes'] as String?,
        createdAt: _dateFromJson(json['createdAt']),
        updatedAt: _dateFromJson(json['updatedAt']),
      );
}

class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.purchaseId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.finalUnitPrice,
    required this.lineTotal,
    this.expiryDate,
    this.batchId,
  });

  final String id;
  final String purchaseId;
  final String productId;
  final double quantity;
  final double unitPrice;
  final double finalUnitPrice;
  final double lineTotal;
  final DateTime? expiryDate;
  final String? batchId;

  PurchaseItem copyWith({
    String? id,
    String? purchaseId,
    String? productId,
    double? quantity,
    double? unitPrice,
    double? finalUnitPrice,
    double? lineTotal,
    DateTime? expiryDate,
    bool clearExpiryDate = false,
    String? batchId,
    bool clearBatchId = false,
  }) =>
      PurchaseItem(
        id: id ?? this.id,
        purchaseId: purchaseId ?? this.purchaseId,
        productId: productId ?? this.productId,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        finalUnitPrice: finalUnitPrice ?? this.finalUnitPrice,
        lineTotal: lineTotal ?? this.lineTotal,
        expiryDate: clearExpiryDate ? null : expiryDate ?? this.expiryDate,
        batchId: clearBatchId ? null : batchId ?? this.batchId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'purchaseId': purchaseId,
        'productId': productId,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'finalUnitPrice': finalUnitPrice,
        'lineTotal': lineTotal,
        if (expiryDate != null) 'expiryDate': expiryDate!.toIso8601String(),
        if (batchId != null) 'batchId': batchId,
      };

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
        id: json['id'] as String? ?? '',
        purchaseId: json['purchaseId'] as String? ?? '',
        productId: json['productId'] as String? ?? '',
        quantity: _doubleFromJson(json['quantity']),
        unitPrice: _doubleFromJson(json['unitPrice']),
        finalUnitPrice: _doubleFromJson(json['finalUnitPrice']),
        lineTotal: _doubleFromJson(json['lineTotal']),
        expiryDate: _nullableDateFromJson(json['expiryDate']),
        batchId: json['batchId'] as String?,
      );
}

class PurchaseTotals {
  const PurchaseTotals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
  });

  final double subtotal;
  final double discount;
  final double tax;
  final double total;
}

class PurchaseListEntry {
  const PurchaseListEntry({required this.purchase, required this.itemCount});

  final Purchase purchase;
  final int itemCount;
}

class PurchaseDetails {
  const PurchaseDetails({required this.purchase, required this.items});

  final Purchase purchase;
  final List<PurchaseItem> items;
}

class PurchaseProductOption {
  const PurchaseProductOption({
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

double _doubleFromJson(Object? value) => value is num ? value.toDouble() : 0;

DateTime _dateFromJson(Object? value) =>
    _nullableDateFromJson(value) ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _nullableDateFromJson(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
