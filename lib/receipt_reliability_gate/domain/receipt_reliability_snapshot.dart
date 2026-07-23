class ReceiptReliabilitySnapshot {
  const ReceiptReliabilitySnapshot({
    required this.receiptId,
    required this.productTextCoverage,
    required this.recoveredOrphans,
    required this.remainingOrphans,
    required this.completeLines,
    required this.partialLines,
    required this.orphanLines,
  });

  factory ReceiptReliabilitySnapshot.fromJson(Map<String, Object?> json) =>
      ReceiptReliabilitySnapshot(
        receiptId: json['receiptId']! as String,
        productTextCoverage: (json['productTextCoverage']! as num).toDouble(),
        recoveredOrphans: json['recoveredOrphans']! as int,
        remainingOrphans: json['remainingOrphans']! as int,
        completeLines: json['completeLines']! as int,
        partialLines: json['partialLines']! as int,
        orphanLines: json['orphanLines']! as int,
      );

  final String receiptId;
  final double productTextCoverage;
  final int recoveredOrphans;
  final int remainingOrphans;
  final int completeLines;
  final int partialLines;
  final int orphanLines;

  Map<String, Object> toJson() => {
        'receiptId': receiptId,
        'productTextCoverage': productTextCoverage,
        'recoveredOrphans': recoveredOrphans,
        'remainingOrphans': remainingOrphans,
        'completeLines': completeLines,
        'partialLines': partialLines,
        'orphanLines': orphanLines,
      };
}
