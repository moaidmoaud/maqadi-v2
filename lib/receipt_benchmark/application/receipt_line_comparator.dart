import '../../receipt_line_builder/domain/receipt_line.dart';
import '../../receipt_line_builder/domain/receipt_line_completeness.dart';
import '../../receipt_line_builder/domain/receipt_line_result.dart';
import '../domain/receipt_benchmark_ground_truth.dart';
import '../domain/receipt_benchmark_result.dart';

class ReceiptLineComparator {
  const ReceiptLineComparator();

  ReceiptLineBenchmarkResult compare({
    required ReceiptBenchmarkGroundTruth groundTruth,
    required ReceiptLineResult actual,
    required Map<String, String> actualIdToFixtureKey,
    required Set<String> elementCorrectionKeys,
  }) {
    final actualEntries = <_ActualLine>[];
    for (final line in actual.lines) {
      final roles = _roles(line, actualIdToFixtureKey);
      actualEntries.add(_ActualLine(
        line: line,
        roles: roles,
        identityKey: roles['product'] ??
            roles.values.whereType<String>().firstOrNull ??
            'actual:${line.id}',
      ));
    }
    final byIdentity = <String, List<_ActualLine>>{};
    for (final entry in actualEntries) {
      byIdentity.putIfAbsent(entry.identityKey, () => []).add(entry);
    }
    final usedActualIds = <String>{};
    final missingLines = <String>[];
    final roleMismatches = <ReceiptRoleMismatch>[];
    final completenessMismatches = <String>[];
    var correct = 0;
    for (final expected in groundTruth.expectedLines) {
      final candidates = byIdentity[expected.identityKey] ?? const [];
      _ActualLine? matched;
      for (final candidate in candidates) {
        if (!usedActualIds.contains(candidate.line.id)) {
          matched = candidate;
          break;
        }
      }
      if (matched == null) {
        missingLines.add(expected.fixtureKey);
        continue;
      }
      usedActualIds.add(matched.line.id);
      var exact = matched.line.completeness == expected.completeness;
      if (!exact) completenessMismatches.add(expected.fixtureKey);
      for (final role in expected.roles.keys) {
        final expectedKey = expected.roles[role];
        final actualKey = matched.roles[role];
        if (expectedKey != actualKey) {
          exact = false;
          roleMismatches.add(ReceiptRoleMismatch(
            expectedLineKey: expected.fixtureKey,
            role: role,
            expectedElementKey: expectedKey,
            actualElementKey: actualKey,
          ));
        }
      }
      if (exact) correct++;
    }
    final unexpectedLines = actualEntries
        .where((entry) => !usedActualIds.contains(entry.line.id))
        .map((entry) => entry.line.id)
        .toList(growable: false);

    final actualUnassigned = actual.unassignedElements
        .map((value) =>
            actualIdToFixtureKey[value.elementId] ??
            'actual:${value.elementId}')
        .toSet();
    final expectedUnassigned = groundTruth.expectedUnassignedKeys.toSet();
    final missingUnassigned = expectedUnassigned.difference(actualUnassigned);
    final unexpectedUnassigned =
        actualUnassigned.difference(expectedUnassigned);

    final precision = _ratio(correct, actual.lines.length);
    final recall = _ratio(correct, groundTruth.expectedLines.length);
    final f1 = precision + recall == 0
        ? 0.0
        : (2 * precision * recall) / (precision + recall);
    final corrections = _manualCorrections(
      groundTruth: groundTruth,
      actualEntries: actualEntries,
      missingLines: missingLines,
      unexpectedLineIds: unexpectedLines,
      roleMismatches: roleMismatches,
      completenessMismatches: completenessMismatches,
      missingUnassigned: missingUnassigned,
      unexpectedUnassigned: unexpectedUnassigned,
      initialKeys: elementCorrectionKeys,
    );
    return ReceiptLineBenchmarkResult(
      expectedLineCount: groundTruth.expectedLines.length,
      actualLineCount: actual.lines.length,
      correctlyGroupedLines: correct,
      missingExpectedLines: missingLines,
      unexpectedLines: unexpectedLines,
      incorrectRoleAttachments: roleMismatches,
      completenessMismatches: completenessMismatches,
      expectedCompletenessCounts:
          _expectedCompletenessCounts(groundTruth.expectedLines),
      actualCompletenessCounts: _actualCompletenessCounts(actual.lines),
      actualUnassignedCount: actual.unassignedElements.length,
      missingExpectedUnassigned: missingUnassigned,
      unexpectedUnassigned: unexpectedUnassigned,
      precision: precision,
      recall: recall,
      f1: f1,
      manualCorrectionsEstimate: corrections,
    );
  }

  Map<String, String?> _roles(
    ReceiptLine line,
    Map<String, String> keys,
  ) =>
      Map.unmodifiable({
        'product': _key(line.productElementId, keys),
        'quantity': _key(line.quantityElementId, keys),
        'price': _key(line.priceElementId, keys),
        'lineTotal': _key(line.lineTotalElementId, keys),
        'discount': _key(line.discountElementId, keys),
        'tax': _key(line.taxElementId, keys),
      });

  String? _key(String? id, Map<String, String> keys) =>
      id == null ? null : keys[id] ?? 'actual:$id';

  double _ratio(int numerator, int denominator) => denominator == 0
      ? numerator == 0
          ? 1.0
          : 0.0
      : numerator / denominator;

  Map<ReceiptLineCompleteness, int> _expectedCompletenessCounts(
    List<ExpectedReceiptLine> lines,
  ) =>
      Map.unmodifiable({
        for (final value in ReceiptLineCompleteness.values)
          value: lines.where((line) => line.completeness == value).length,
      });

  Map<ReceiptLineCompleteness, int> _actualCompletenessCounts(
    List<ReceiptLine> lines,
  ) =>
      Map.unmodifiable({
        for (final value in ReceiptLineCompleteness.values)
          value: lines.where((line) => line.completeness == value).length,
      });

  int _manualCorrections({
    required ReceiptBenchmarkGroundTruth groundTruth,
    required List<_ActualLine> actualEntries,
    required List<String> missingLines,
    required List<String> unexpectedLineIds,
    required List<ReceiptRoleMismatch> roleMismatches,
    required List<String> completenessMismatches,
    required Set<String> missingUnassigned,
    required Set<String> unexpectedUnassigned,
    required Set<String> initialKeys,
  }) {
    final correctedKeys = Set<String>.from(initialKeys);
    var count = correctedKeys.length;
    final expectedById = {
      for (final line in groundTruth.expectedLines) line.fixtureKey: line,
    };
    for (final id in missingLines) {
      final keys = expectedById[id]!.referencedKeys;
      if (keys.intersection(correctedKeys).isEmpty) {
        count++;
        correctedKeys.addAll(keys);
      }
    }
    final actualById = {
      for (final entry in actualEntries) entry.line.id: entry,
    };
    for (final id in unexpectedLineIds) {
      final keys = actualById[id]!.roles.values.whereType<String>().toSet();
      if (keys.intersection(correctedKeys).isEmpty) {
        count++;
        correctedKeys.addAll(keys);
      }
    }
    for (final mismatch in roleMismatches) {
      final keys = {
        mismatch.expectedElementKey,
        mismatch.actualElementKey,
      }.whereType<String>().toSet();
      if (keys.intersection(correctedKeys).isEmpty) {
        count++;
        correctedKeys.addAll(keys);
      }
    }
    for (final lineId in completenessMismatches) {
      final keys = expectedById[lineId]!.referencedKeys;
      if (keys.intersection(correctedKeys).isEmpty) {
        count++;
        correctedKeys.addAll(keys);
      }
    }
    for (final key in {...missingUnassigned, ...unexpectedUnassigned}) {
      if (correctedKeys.add(key)) count++;
    }
    return count;
  }
}

class _ActualLine {
  const _ActualLine({
    required this.line,
    required this.roles,
    required this.identityKey,
  });

  final ReceiptLine line;
  final Map<String, String?> roles;
  final String identityKey;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
