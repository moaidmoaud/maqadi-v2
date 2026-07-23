import '../domain/candidate_generation_diagnostics.dart';

class CandidateNormalizationResult {
  CandidateNormalizationResult({
    required this.originalText,
    required this.preCorrectionNormalizedText,
    required this.normalizedText,
    required Iterable<CandidateNormalizationOperation> appliedOperations,
  }) : appliedOperations = List.unmodifiable(appliedOperations);

  final String originalText;
  final String preCorrectionNormalizedText;
  final String normalizedText;
  final List<CandidateNormalizationOperation> appliedOperations;
}

class CandidateTextNormalizer {
  const CandidateTextNormalizer();

  static final RegExp _punctuation = RegExp(
    r'[^a-z0-9\u0600-\u06ff]+',
    caseSensitive: false,
  );
  static final RegExp _arabicPunctuation = RegExp(r'[\u060c\u061b\u061f]');
  static final RegExp _repeatedWhitespace = RegExp(r'\s+');
  static const Map<String, String> _latinFoldGroups = {
    'àáâãäåāăąǎǟǡǻ': 'a',
    'çćĉċč': 'c',
    'ďđð': 'd',
    'èéêëēĕėęě': 'e',
    'ĝğġģ': 'g',
    'ĥħ': 'h',
    'ìíîïĩīĭįıǐ': 'i',
    'ĵ': 'j',
    'ķ': 'k',
    'ĺļľŀł': 'l',
    'ñńņňŉ': 'n',
    'òóôõöøōŏőǒǿ': 'o',
    'ŕŗř': 'r',
    'śŝşš': 's',
    'ţťŧ': 't',
    'ùúûüũūŭůűųǔ': 'u',
    'ŵ': 'w',
    'ýÿŷ': 'y',
    'źżž': 'z',
    'æ': 'ae',
    'œ': 'oe',
    'ß': 'ss',
    'þ': 'th',
  };

  String normalize(String value) => normalizeWithTrace(value).normalizedText;

  CandidateNormalizationResult normalizeWithTrace(String value) {
    final operations = <CandidateNormalizationOperation>[];
    var current = value;

    final lowercased = current.toLowerCase();
    if (lowercased != current) {
      operations.add(CandidateNormalizationOperation.lowercased);
    }
    current = lowercased;

    final folded = _foldAccentedLatin(current);
    if (folded != current) {
      operations.add(CandidateNormalizationOperation.foldedAccentedLatin);
    }
    current = folded;

    final withoutPunctuation = current
        .replaceAll(_arabicPunctuation, ' ')
        .replaceAll(_punctuation, ' ');
    if (withoutPunctuation != current) {
      operations.add(CandidateNormalizationOperation.removedPunctuation);
    }
    current = withoutPunctuation;

    final collapsed = current.replaceAll(_repeatedWhitespace, ' ').trim();
    if (collapsed != current) {
      operations.add(CandidateNormalizationOperation.collapsedWhitespace);
    }
    final preCorrection = collapsed;

    final corrected = _correctOcrZeroBetweenLetters(preCorrection);
    if (corrected != preCorrection) {
      operations
          .add(CandidateNormalizationOperation.correctedOcrZeroBetweenLetters);
    }

    return CandidateNormalizationResult(
      originalText: value,
      preCorrectionNormalizedText: preCorrection,
      normalizedText: corrected,
      appliedOperations: operations,
    );
  }

  String _foldAccentedLatin(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x0300 && rune <= 0x036f) continue;
      final character = String.fromCharCode(rune);
      var replacement = character;
      for (final entry in _latinFoldGroups.entries) {
        if (entry.key.contains(character)) {
          replacement = entry.value;
          break;
        }
      }
      buffer.write(replacement);
    }
    return buffer.toString();
  }

  String _correctOcrZeroBetweenLetters(String value) =>
      value.split(' ').map(_correctToken).join(' ');

  String _correctToken(String token) {
    if (token.length < 4 ||
        token.codeUnits.any(
          (value) => _isAsciiDigit(value) && value != _zeroCodeUnit,
        )) {
      return token;
    }
    final values = token.codeUnits.toList(growable: false);
    final corrected = StringBuffer();
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      final betweenLetters = value == _zeroCodeUnit &&
          index > 0 &&
          index < values.length - 1 &&
          _isAsciiLetter(values[index - 1]) &&
          _isAsciiLetter(values[index + 1]);
      corrected.writeCharCode(betweenLetters ? _lowercaseOCodeUnit : value);
    }
    return corrected.toString();
  }

  static const int _zeroCodeUnit = 0x30;
  static const int _lowercaseOCodeUnit = 0x6f;

  bool _isAsciiLetter(int value) =>
      (value >= 0x61 && value <= 0x7a) || (value >= 0x41 && value <= 0x5a);

  bool _isAsciiDigit(int value) => value >= 0x30 && value <= 0x39;
}
