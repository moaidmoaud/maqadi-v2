import 'package:flutter_test/flutter_test.dart';
import 'package:maqadi_v2/product_matching/engine/text_normalizer.dart';

void main() {
  group('TextNormalizer', () {
    const normalizer = TextNormalizer();

    test('lowercases English text', () {
      expect(normalizer.normalize('Fresh MILK'), 'fresh milk');
    });

    test('normalizes common Arabic character variants and marks', () {
      expect(normalizer.normalize('إِلَى مَدْرَسَةٍ'), 'الي مدرسه');
      expect(normalizer.normalize('مـؤونة'), 'موونه');
    });

    test('removes punctuation and preserves letters and numbers', () {
      expect(normalizer.normalize('Milk, 2L! #1'), 'milk 2l 1');
    });

    test('collapses duplicated whitespace and trims', () {
      expect(normalizer.normalize('  whole\t  milk\n '), 'whole milk');
    });

    test('accepts future normalization rules without redesign', () {
      const custom = TextNormalizer(rules: [_ReplaceMilkRule()]);
      expect(custom.normalize('milk'), 'dairy');
    });
  });
}

class _ReplaceMilkRule implements TextNormalizationRule {
  const _ReplaceMilkRule();

  @override
  String apply(String text) => text.replaceAll('milk', 'dairy');
}
