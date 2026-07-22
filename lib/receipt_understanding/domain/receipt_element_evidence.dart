import 'receipt_relative_position.dart';

class ReceiptElementEvidence {
  ReceiptElementEvidence({
    required this.matchedRule,
    required this.normalizedText,
    required this.relativePosition,
    required Iterable<String> neighbourReferences,
    required Iterable<String> matchedStructuralPatterns,
    required this.ocrConfidence,
    this.summary,
  })  : neighbourReferences = List.unmodifiable(neighbourReferences),
        matchedStructuralPatterns =
            List.unmodifiable(matchedStructuralPatterns);

  final String matchedRule;
  final String normalizedText;
  final ReceiptRelativePosition relativePosition;
  final List<String> neighbourReferences;
  final List<String> matchedStructuralPatterns;
  final double? ocrConfidence;
  final String? summary;
}
