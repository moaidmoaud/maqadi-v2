import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reliability gate is Flutter-free, read-only, and dependency-light', () {
    final files =
        Directory('lib/receipt_reliability_gate').listSync(recursive: true);

    for (final file in files.whereType<File>()) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: file.path);
      expect(source, isNot(contains('Repository')), reason: file.path);
      expect(source, isNot(contains('SharedPreferences')), reason: file.path);
      expect(source, isNot(contains('.save(')), reason: file.path);
      expect(source, isNot(contains('.write(')), reason: file.path);
      expect(source, isNot(contains('.update(')), reason: file.path);
      expect(source, isNot(contains('.delete(')), reason: file.path);
    }
  });
}
