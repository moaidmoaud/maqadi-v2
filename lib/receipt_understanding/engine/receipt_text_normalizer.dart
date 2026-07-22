class ReceiptTextNormalizer {
  const ReceiptTextNormalizer();

  String normalize(String input) {
    var value = input.toLowerCase();
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    for (var index = 0; index < 10; index++) {
      value = value
          .replaceAll(arabicDigits[index], '$index')
          .replaceAll(persianDigits[index], '$index');
    }
    value = value
        .replaceAll(RegExp(r'[أإآٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('٫', '.')
        .replaceAll('٬', ',')
        .replaceAll('−', '-')
        .replaceAll('–', '-')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return value;
  }
}
