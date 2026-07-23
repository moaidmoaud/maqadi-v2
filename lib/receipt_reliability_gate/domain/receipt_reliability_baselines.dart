import 'receipt_reliability_snapshot.dart';

abstract final class ReceiptReliabilityBaselines {
  static const dan0001 = ReceiptReliabilitySnapshot(
    receiptId: 'DAN-0001',
    productTextCoverage: 0.6666666666666666,
    recoveredOrphans: 0,
    remainingOrphans: 1,
    completeLines: 1,
    partialLines: 1,
    orphanLines: 1,
  );

  static ReceiptReliabilitySnapshot dan0001ForReceipt(String receiptId) =>
      ReceiptReliabilitySnapshot(
        receiptId: receiptId,
        productTextCoverage: dan0001.productTextCoverage,
        recoveredOrphans: dan0001.recoveredOrphans,
        remainingOrphans: dan0001.remainingOrphans,
        completeLines: dan0001.completeLines,
        partialLines: dan0001.partialLines,
        orphanLines: dan0001.orphanLines,
      );
}
