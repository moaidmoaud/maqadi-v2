enum CandidateNormalizationOperation {
  lowercased,
  foldedAccentedLatin,
  removedPunctuation,
  collapsedWhitespace,
  correctedOcrZeroBetweenLetters,
}

enum CandidateGenerationDiagnosticReason {
  candidatesGenerated,
  noProductText,
  emptyCatalog,
  noValidCatalogEntries,
  noCandidateMatch,
}

class CandidateCatalogPreviewEntry {
  const CandidateCatalogPreviewEntry({
    required this.productId,
    required this.normalizedName,
  });

  factory CandidateCatalogPreviewEntry.fromJson(Map<String, Object?> json) =>
      CandidateCatalogPreviewEntry(
        productId: json['productId']! as String,
        normalizedName: json['normalizedName']! as String,
      );

  final String productId;
  final String normalizedName;

  Map<String, Object> toJson() => {
        'productId': productId,
        'normalizedName': normalizedName,
      };
}

class CandidateGenerationDiagnostics {
  CandidateGenerationDiagnostics({
    required this.reason,
    required this.catalogEntryCount,
    required this.validCatalogEntryCount,
    required this.invalidCatalogEntryCount,
    required this.duplicateProductIdCount,
    required this.evaluatedEntryCount,
    required this.rejectedNoTextCount,
    required this.rejectedNoTokenOverlapCount,
    required this.acceptedCount,
    required Iterable<CandidateCatalogPreviewEntry> catalogPreview,
  }) : catalogPreview = List.unmodifiable(catalogPreview);

  factory CandidateGenerationDiagnostics.fromJson(
    Map<String, Object?> json,
  ) =>
      CandidateGenerationDiagnostics(
        reason: CandidateGenerationDiagnosticReason.values.byName(
          json['reason']! as String,
        ),
        catalogEntryCount: json['catalogEntryCount']! as int,
        validCatalogEntryCount: json['validCatalogEntryCount']! as int,
        invalidCatalogEntryCount: json['invalidCatalogEntryCount']! as int,
        duplicateProductIdCount: json['duplicateProductIdCount']! as int,
        evaluatedEntryCount: json['evaluatedEntryCount']! as int,
        rejectedNoTextCount: json['rejectedNoTextCount']! as int,
        rejectedNoTokenOverlapCount:
            json['rejectedNoTokenOverlapCount']! as int,
        acceptedCount: json['acceptedCount']! as int,
        catalogPreview: (json['catalogPreview']! as List<Object?>).map(
          (value) => CandidateCatalogPreviewEntry.fromJson(
            value! as Map<String, Object?>,
          ),
        ),
      );

  final CandidateGenerationDiagnosticReason reason;
  final int catalogEntryCount;
  final int validCatalogEntryCount;
  final int invalidCatalogEntryCount;
  final int duplicateProductIdCount;
  final int evaluatedEntryCount;
  final int rejectedNoTextCount;
  final int rejectedNoTokenOverlapCount;
  final int acceptedCount;
  final List<CandidateCatalogPreviewEntry> catalogPreview;

  Map<String, Object> toJson() => {
        'reason': reason.name,
        'catalogEntryCount': catalogEntryCount,
        'validCatalogEntryCount': validCatalogEntryCount,
        'invalidCatalogEntryCount': invalidCatalogEntryCount,
        'duplicateProductIdCount': duplicateProductIdCount,
        'evaluatedEntryCount': evaluatedEntryCount,
        'rejectedNoTextCount': rejectedNoTextCount,
        'rejectedNoTokenOverlapCount': rejectedNoTokenOverlapCount,
        'acceptedCount': acceptedCount,
        'catalogPreview': [
          for (final value in catalogPreview) value.toJson(),
        ],
      };
}
