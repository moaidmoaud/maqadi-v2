class InventoryBatch {
  InventoryBatch({
    required this.id,
    required this.quantity,
    required this.receivedAt,
    this.expiresAt,
    this.note,
  });

  String id;
  double quantity;
  DateTime receivedAt;
  DateTime? expiresAt;
  String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'quantity': quantity,
    'receivedAt': receivedAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'note': note,
  };

  factory InventoryBatch.fromJson(Map<String, dynamic> json) => InventoryBatch(
    id:
        json['id'] as String? ??
        DateTime.now().microsecondsSinceEpoch.toString(),
    quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
    receivedAt:
        DateTime.tryParse(json['receivedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    note: json['note'] as String?,
  );
}

class PantryItem {
  PantryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.minimum,
    required this.unit,
    required this.location,
    double quantity = 0,
    List<InventoryBatch>? batches,
  }) : batches =
           batches ??
           (quantity > 0
               ? [
                   InventoryBatch(
                     id: '${id}_initial',
                     quantity: quantity,
                     receivedAt: DateTime.fromMillisecondsSinceEpoch(
                       0,
                       isUtc: true,
                     ),
                     note: 'رصيد افتتاحي',
                   ),
                 ]
               : []);

  final String id;
  String name;
  String category;
  double minimum;
  String unit;
  String location;
  final List<InventoryBatch> batches;

  double get quantity =>
      batches.fold(0, (total, batch) => total + batch.quantity);

  bool get isLow => quantity <= minimum;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    // Kept for older app versions that do not understand batches yet.
    'quantity': quantity,
    'minimum': minimum,
    'unit': unit,
    'location': location,
    'batches': batches.map((batch) => batch.toJson()).toList(),
  };

  factory PantryItem.fromJson(Map<String, dynamic> json) {
    final id =
        json['id'] as String? ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final legacyQuantity = (json['quantity'] as num?)?.toDouble() ?? 0;
    final decodedBatches = ((json['batches'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (batch) => InventoryBatch.fromJson(Map<String, dynamic>.from(batch)),
        )
        .where((batch) => batch.quantity > 0)
        .toList();

    if (decodedBatches.isEmpty && legacyQuantity > 0) {
      decodedBatches.add(
        InventoryBatch(
          id: '${id}_legacy',
          quantity: legacyQuantity,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          note: 'بيانات مرحّلة',
        ),
      );
    }

    return PantryItem(
      id: id,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? 'أخرى',
      minimum: (json['minimum'] as num?)?.toDouble() ?? 1,
      unit: json['unit'] as String? ?? 'حبة',
      location: json['location'] as String? ?? 'المخزن',
      batches: decodedBatches,
    );
  }
}

class PantryMovement {
  PantryMovement({
    required this.id,
    required this.pantryItemId,
    required this.productName,
    required this.type,
    required this.amount,
    required this.unit,
    required this.createdAt,
    this.note,
    Map<String, double>? batchAllocations,
  }) : batchAllocations = batchAllocations ?? const {};

  final String id;
  final String pantryItemId;
  final String productName;
  final String type;
  final double amount;
  final String unit;
  final DateTime createdAt;
  final String? note;
  final Map<String, double> batchAllocations;

  Map<String, dynamic> toJson() => {
    'id': id,
    'pantryItemId': pantryItemId,
    'productName': productName,
    'type': type,
    'amount': amount,
    'unit': unit,
    'createdAt': createdAt.toIso8601String(),
    'note': note,
    if (batchAllocations.isNotEmpty) 'batchAllocations': batchAllocations,
  };

  factory PantryMovement.fromJson(Map<String, dynamic> json) => PantryMovement(
    id:
        json['id'] as String? ??
        DateTime.now().microsecondsSinceEpoch.toString(),
    pantryItemId: json['pantryItemId'] as String? ?? '',
    productName: json['productName'] as String? ?? '',
    type: json['type'] as String? ?? 'تعديل',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    unit: json['unit'] as String? ?? 'حبة',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    note: json['note'] as String?,
    batchAllocations: ((json['batchAllocations'] as Map?) ?? const {}).map(
      (key, value) =>
          MapEntry(key.toString(), value is num ? value.toDouble() : 0),
    ),
  );
}
