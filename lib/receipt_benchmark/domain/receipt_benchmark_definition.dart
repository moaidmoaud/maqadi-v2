import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import 'receipt_benchmark_ground_truth.dart';

class ReceiptBenchmarkFixtureBlock {
  const ReceiptBenchmarkFixtureBlock({
    required this.fixtureKey,
    required this.text,
    required this.confidence,
    required this.region,
  });

  final String fixtureKey;
  final String text;
  final double? confidence;
  final ReceiptOcrRegion? region;

  factory ReceiptBenchmarkFixtureBlock.fromJson(Map<String, Object?> json) {
    final region = json['region'] as Map<String, Object?>?;
    return ReceiptBenchmarkFixtureBlock(
      fixtureKey: json['fixtureKey']! as String,
      text: json['text']! as String,
      confidence: (json['confidence'] as num?)?.toDouble(),
      region: region == null
          ? null
          : ReceiptOcrRegion(
              x: (region['x']! as num).toDouble(),
              y: (region['y']! as num).toDouble(),
              width: (region['width']! as num).toDouble(),
              height: (region['height']! as num).toDouble(),
            ),
    );
  }

  ReceiptOcrBlock toOcrBlock() => ReceiptOcrBlock(
        text: text,
        lines: const [],
        confidence: confidence,
        region: region,
      );

  String get signature => signatureFor(text, region);

  static String signatureFor(String text, ReceiptOcrRegion? region) {
    if (region == null) return '$text|none';
    String fixed(double value) => value.toStringAsFixed(6);
    return [
      text,
      fixed(region.x),
      fixed(region.y),
      fixed(region.width),
      fixed(region.height),
    ].join('|');
  }
}

class ReceiptBenchmarkDefinition {
  ReceiptBenchmarkDefinition({
    required this.receiptId,
    required this.fixtureVersion,
    required this.syntheticFixture,
    required this.privateImageCommitted,
    required this.calibrationNotes,
    required Iterable<ReceiptBenchmarkFixtureBlock> fixtureBlocks,
    required this.groundTruth,
  }) : fixtureBlocks = List.unmodifiable(fixtureBlocks);

  final String receiptId;
  final String fixtureVersion;
  final bool syntheticFixture;
  final bool privateImageCommitted;
  final String calibrationNotes;
  final List<ReceiptBenchmarkFixtureBlock> fixtureBlocks;
  final ReceiptBenchmarkGroundTruth groundTruth;

  factory ReceiptBenchmarkDefinition.fromJson(Map<String, Object?> json) =>
      ReceiptBenchmarkDefinition(
        receiptId: json['receiptId']! as String,
        fixtureVersion: json['fixtureVersion']! as String,
        syntheticFixture: json['syntheticFixture']! as bool,
        privateImageCommitted: json['privateImageCommitted']! as bool,
        calibrationNotes: json['calibrationNotes']! as String,
        fixtureBlocks: (json['fixtureBlocks']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map(ReceiptBenchmarkFixtureBlock.fromJson),
        groundTruth: ReceiptBenchmarkGroundTruth.fromJson(
          json['groundTruth']! as Map<String, Object?>,
        ),
      );

  ReceiptOcrResult toOcrResult() => ReceiptOcrResult(
        text: fixtureBlocks.map((block) => block.text).join('\n'),
        blocks: List.unmodifiable(
          fixtureBlocks.map((block) => block.toOcrBlock()),
        ),
      );
}
