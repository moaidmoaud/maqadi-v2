import 'dart:convert';

import '../domain/receipt_line_completeness.dart';

class ReceiptLineIdGenerator {
  const ReceiptLineIdGenerator();

  String generate({
    required ReceiptLineCompleteness completeness,
    required Map<String, String?> roles,
  }) {
    final input = StringBuffer(completeness.name);
    for (final entry in roles.entries) {
      if (entry.value != null) input.write('|${entry.key}:${entry.value}');
    }
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    for (final byte in utf8.encode(input.toString())) {
      hash ^= BigInt.from(byte);
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
