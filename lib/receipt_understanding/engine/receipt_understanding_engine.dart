import '../../receipt_ocr/domain/receipt_ocr_result.dart';
import '../domain/receipt_element.dart';
import '../domain/receipt_element_evidence.dart';
import '../domain/receipt_relative_position.dart';
import 'receipt_classification_rules.dart';
import 'receipt_element_id_generator.dart';
import 'receipt_layout_analyzer.dart';
import 'receipt_text_normalizer.dart';

class ReceiptUnderstandingEngine {
  const ReceiptUnderstandingEngine({
    ReceiptTextNormalizer normalizer = const ReceiptTextNormalizer(),
    ReceiptLayoutAnalyzer layoutAnalyzer = const ReceiptLayoutAnalyzer(),
    ReceiptClassificationRules rules = const ReceiptClassificationRules(),
    ReceiptElementIdGenerator idGenerator = const ReceiptElementIdGenerator(),
  })  : _normalizer = normalizer,
        _layoutAnalyzer = layoutAnalyzer,
        _rules = rules,
        _idGenerator = idGenerator;

  final ReceiptTextNormalizer _normalizer;
  final ReceiptLayoutAnalyzer _layoutAnalyzer;
  final ReceiptClassificationRules _rules;
  final ReceiptElementIdGenerator _idGenerator;

  List<ReceiptElement> classify(List<ReceiptOcrBlock> orderedBlocks) {
    if (orderedBlocks.isEmpty) return const [];
    final bounds = _layoutAnalyzer.bounds(orderedBlocks);
    final normalized = [
      for (final block in orderedBlocks) _normalizer.normalize(block.text),
    ];
    final positions = [
      for (final block in orderedBlocks)
        _layoutAnalyzer.relativePosition(block.region, bounds),
    ];
    final ids = _idGenerator.generate([
      for (var index = 0; index < orderedBlocks.length; index++)
        (
          text: normalized[index],
          regionKey: _layoutAnalyzer.normalizedRegionKey(
            orderedBlocks[index].region,
            bounds,
          ),
        ),
    ]);
    final storeIndex = _storeNameCandidate(
      orderedBlocks,
      normalized,
      positions,
      bounds,
    );

    return List.unmodifiable([
      for (var index = 0; index < orderedBlocks.length; index++)
        _classifyBlock(
          index: index,
          blocks: orderedBlocks,
          normalized: normalized,
          positions: positions,
          ids: ids,
          storeIndex: storeIndex,
        ),
    ]);
  }

  ReceiptElement _classifyBlock({
    required int index,
    required List<ReceiptOcrBlock> blocks,
    required List<String> normalized,
    required List<ReceiptRelativePosition> positions,
    required List<String> ids,
    required int? storeIndex,
  }) {
    final block = blocks[index];
    final previousIndex = index == 0 ? null : index - 1;
    final nextIndex = index + 1 == blocks.length ? null : index + 1;
    final features = ReceiptBlockFeatures(
      id: ids[index],
      normalizedText: normalized[index],
      relativePosition: positions[index],
      previousId: previousIndex == null ? null : ids[previousIndex],
      previousText: previousIndex == null ? null : normalized[previousIndex],
      nextId: nextIndex == null ? null : ids[nextIndex],
      nextText: nextIndex == null ? null : normalized[nextIndex],
      isStoreNameCandidate: index == storeIndex,
    );
    final classification = _rules.classify(features);
    final neighbours =
        [features.previousId, features.nextId].whereType<String>();
    final confidence = block.confidence;
    final safeConfidence =
        confidence != null && confidence.isFinite ? confidence : null;
    return ReceiptElement(
      id: ids[index],
      text: block.text,
      boundingBox: _layoutAnalyzer.validRegion(block.region),
      confidence: safeConfidence,
      type: classification.type,
      evidence: ReceiptElementEvidence(
        matchedRule: classification.matchedRule,
        normalizedText: normalized[index],
        relativePosition: positions[index],
        neighbourReferences: neighbours,
        matchedStructuralPatterns: classification.matchedPatterns,
        ocrConfidence: safeConfidence,
        summary: classification.summary,
      ),
    );
  }

  int? _storeNameCandidate(
    List<ReceiptOcrBlock> blocks,
    List<String> normalized,
    List<ReceiptRelativePosition> positions,
    ReceiptDocumentBounds? bounds,
  ) {
    if (bounds == null) return null;
    int? selected;
    var selectedScore = double.negativeInfinity;
    for (var index = 0; index < blocks.length; index++) {
      if (positions[index] != ReceiptRelativePosition.header ||
          !_rules.looksPrimarilyTextual(normalized[index]) ||
          _rules.isSpecificStructuralText(normalized[index])) {
        continue;
      }
      final region = _layoutAnalyzer.validRegion(blocks[index].region);
      if (region == null) continue;
      final relativeHeight = region.height / bounds.height;
      final relativeWidth = region.width / bounds.width;
      final center = region.x + (region.width / 2);
      final documentCenter = bounds.left + (bounds.width / 2);
      final alignment =
          1 - ((center - documentCenter).abs() / bounds.width).clamp(0, 1);
      final score = (relativeHeight * 3) + relativeWidth + alignment;
      if (score > selectedScore) {
        selected = index;
        selectedScore = score;
      }
    }
    return selected;
  }
}
