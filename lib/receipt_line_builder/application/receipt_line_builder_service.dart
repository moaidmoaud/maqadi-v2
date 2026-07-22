import '../../receipt_understanding/domain/receipt_element.dart';
import '../../receipt_understanding/domain/receipt_element_type.dart';
import '../domain/receipt_line.dart';
import '../domain/receipt_line_completeness.dart';
import '../domain/receipt_line_evidence.dart';
import '../domain/receipt_line_failure.dart';
import '../domain/receipt_line_result.dart';
import '../engine/receipt_line_builder_engine.dart';

class ReceiptLineBuilderService {
  const ReceiptLineBuilderService({
    ReceiptLineBuilderEngine engine = const ReceiptLineBuilderEngine(),
  }) : _engine = engine;

  final ReceiptLineBuilderEngine _engine;

  Future<ReceiptLineResult> build(List<ReceiptElement> elements) async {
    final ids = <String>{};
    final invalidGeometryIds = <String>{};
    for (final element in elements) {
      if (element.id.isEmpty || !ids.add(element.id)) {
        throw ReceiptLineFailure(
          code: ReceiptLineFailureCode.duplicateElementId,
          message: 'Receipt element IDs must be unique and non-empty.',
          elementId: element.id,
        );
      }
      final region = element.boundingBox;
      if (region != null &&
          (!region.x.isFinite ||
              !region.y.isFinite ||
              !region.width.isFinite ||
              !region.height.isFinite ||
              region.width <= 0 ||
              region.height <= 0)) {
        invalidGeometryIds.add(element.id);
      }
    }
    try {
      final result = _engine.build(List.unmodifiable(elements));
      _verify(
        result,
        {for (final element in elements) element.id: element},
        invalidGeometryIds,
      );
      return result;
    } on ReceiptLineFailure {
      rethrow;
    } catch (error) {
      throw ReceiptLineFailure(
        code: ReceiptLineFailureCode.groupingFailed,
        message: 'Receipt elements could not be grouped into lines.',
        cause: error,
      );
    }
  }

  void _verify(
    ReceiptLineResult result,
    Map<String, ReceiptElement> elements,
    Set<String> invalidGeometryIds,
  ) {
    final assigned = <String>{};
    for (final line in result.lines) {
      _verifyLine(line, elements);
      for (final id in line.referencedElementIds) {
        if (!assigned.add(id)) {
          throw ReceiptLineFailure(
            code: ReceiptLineFailureCode.duplicateRoleAssignment,
            message: 'A receipt element was assigned to multiple line roles.',
            elementId: id,
          );
        }
      }
    }
    final unassigned = <String>{};
    for (final value in result.unassignedElements) {
      if (!elements.containsKey(value.elementId)) {
        _invalidReference(value.elementId);
      }
      if (!unassigned.add(value.elementId) ||
          assigned.contains(value.elementId)) {
        throw ReceiptLineFailure(
          code: ReceiptLineFailureCode.duplicateRoleAssignment,
          message: 'A receipt element has conflicting output assignments.',
          elementId: value.elementId,
        );
      }
      _verifyEvidenceReferences(value.evidence, elements);
    }
    for (final failure in result.failures) {
      final id = failure.elementId;
      if (id != null && !elements.containsKey(id)) _invalidReference(id);
    }
    for (final id in invalidGeometryIds) {
      final reported = result.failures.any((failure) =>
          failure.code == ReceiptLineFailureCode.invalidGeometry &&
          failure.elementId == id);
      if (!reported || !unassigned.contains(id)) {
        throw ReceiptLineFailure(
          code: ReceiptLineFailureCode.invalidGeometry,
          message: 'Invalid geometry was not safely isolated.',
          elementId: id,
        );
      }
    }
    final accounted = {...assigned, ...unassigned};
    for (final id in elements.keys) {
      if (!accounted.contains(id)) _invalidReference(id);
    }
  }

  void _verifyLine(
    ReceiptLine line,
    Map<String, ReceiptElement> elements,
  ) {
    final roleValues = <ReceiptElementType, String?>{
      ReceiptElementType.productName: line.productElementId,
      ReceiptElementType.price: line.priceElementId,
      ReceiptElementType.quantity: line.quantityElementId,
      ReceiptElementType.discount: line.discountElementId,
      ReceiptElementType.tax: line.taxElementId,
      ReceiptElementType.total: line.lineTotalElementId,
    };
    for (final entry in roleValues.entries) {
      final id = entry.value;
      if (id == null) continue;
      final element = elements[id];
      if (element == null) _invalidReference(id);
      if (element.type != entry.key) {
        throw ReceiptLineFailure(
          code: ReceiptLineFailureCode.invalidReference,
          message: 'A receipt line role references an incompatible element.',
          elementId: id,
        );
      }
      final region = element.boundingBox;
      if (region == null ||
          !region.x.isFinite ||
          !region.y.isFinite ||
          !region.width.isFinite ||
          !region.height.isFinite ||
          region.width <= 0 ||
          region.height <= 0) {
        throw ReceiptLineFailure(
          code: ReceiptLineFailureCode.invalidGeometry,
          message: 'Elements without usable geometry cannot be grouped.',
          elementId: id,
        );
      }
    }
    final expected = line.productElementId == null
        ? ReceiptLineCompleteness.orphan
        : line.priceElementId == null
            ? ReceiptLineCompleteness.partial
            : ReceiptLineCompleteness.complete;
    if (line.completeness != expected ||
        line.evidence.anchorElementId != line.productElementId) {
      throw const ReceiptLineFailure(
        code: ReceiptLineFailureCode.invalidReference,
        message: 'Receipt line completeness or anchor evidence is invalid.',
      );
    }
    _verifyEvidenceReferences(line.evidence, elements);
  }

  void _verifyEvidenceReferences(
    ReceiptLineEvidence evidence,
    Map<String, ReceiptElement> elements,
  ) {
    final references = <String>{
      if (evidence.anchorElementId != null) evidence.anchorElementId!,
      ...evidence.attachedElementIds,
      ...evidence.normalizedVerticalDistances.keys,
      ...evidence.normalizedHorizontalDistances.keys,
      ...evidence.overlapMetrics.keys,
      ...evidence.columnEvidence.keys,
      ...evidence.rejectedCandidates.keys,
    };
    for (final id in references) {
      if (!elements.containsKey(id)) _invalidReference(id);
    }
  }

  Never _invalidReference(String id) => throw ReceiptLineFailure(
        code: ReceiptLineFailureCode.invalidReference,
        message: 'A receipt line references an unknown element.',
        elementId: id,
      );
}
