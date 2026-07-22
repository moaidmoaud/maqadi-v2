class CandidateTextNormalizer {
  const CandidateTextNormalizer();

  static final RegExp _punctuation = RegExp(
    r'[^a-z0-9\u0600-\u06ff]+',
    caseSensitive: false,
  );
  static final RegExp _arabicPunctuation = RegExp(r'[\u060c\u061b\u061f]');
  static final RegExp _repeatedWhitespace = RegExp(r'\s+');

  String normalize(String value) => value
      .toLowerCase()
      .replaceAll(_arabicPunctuation, ' ')
      .replaceAll(_punctuation, ' ')
      .replaceAll(_repeatedWhitespace, ' ')
      .trim();
}
