import 'dart:convert';

class ReceiptElementIdGenerator {
  const ReceiptElementIdGenerator();

  String baseId({required String normalizedText, required String regionKey}) {
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    for (final byte in utf8.encode('$normalizedText|$regionKey')) {
      hash ^= BigInt.from(byte);
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  List<String> generate(List<({String text, String regionKey})> keys) {
    final occurrences = <String, int>{};
    return List.unmodifiable([
      for (final key in keys)
        _withOccurrence(
          baseId(normalizedText: key.text, regionKey: key.regionKey),
          occurrences,
        ),
    ]);
  }

  String _withOccurrence(String base, Map<String, int> occurrences) {
    final occurrence = occurrences[base] ?? 0;
    occurrences[base] = occurrence + 1;
    return occurrence == 0 ? base : '$base-$occurrence';
  }
}
