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

  static ReceiptReliabilitySnapshot? forBenchmark(String benchmarkId) =>
      switch (benchmarkId) {
        'DAN-0001' => dan0001,
        _ => null,
      };
}
