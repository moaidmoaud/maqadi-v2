abstract interface class TextNormalizationRule {
  String apply(String value);
}

class TextNormalizer {
  const TextNormalizer({
    this.rules = const [
      EnglishLowercaseRule(),
      ArabicCharacterRule(),
      PunctuationRule(),
      WhitespaceRule(),
    ],
  });

  final List<TextNormalizationRule> rules;

  String normalize(String value) {
    var result = value;
    for (final rule in rules) {
      result = rule.apply(result);
    }
    return result;
  }
}

class EnglishLowercaseRule implements TextNormalizationRule {
  const EnglishLowercaseRule();

  @override
  String apply(String value) => value.toLowerCase();
}

class ArabicCharacterRule implements TextNormalizationRule {
  const ArabicCharacterRule();

  @override
  String apply(String value) => value
      .replaceAll(RegExp('[\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
      .replaceAll('ـ', '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');
}

class PunctuationRule implements TextNormalizationRule {
  const PunctuationRule();

  static final _punctuation = RegExp(
    r'''[!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~،؛؟]''',
  );

  @override
  String apply(String value) => value.replaceAll(_punctuation, ' ');
}

class WhitespaceRule implements TextNormalizationRule {
  const WhitespaceRule();

  @override
  String apply(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
