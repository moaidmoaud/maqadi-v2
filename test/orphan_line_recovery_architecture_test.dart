import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recovery domain and application remain Flutter-free and read-only', () {
    final files = [
      File(
        'lib/orphan_line_recovery/domain/orphan_line_recovery_result.dart',
      ),
      File(
        'lib/orphan_line_recovery/application/orphan_line_recovery_service.dart',
      ),
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:flutter/')));
      expect(source, isNot(contains('Repository')));
      expect(source, isNot(contains('SharedPreferences')));
      expect(source, isNot(contains('.save(')));
      expect(source, isNot(contains('.write(')));
      expect(source, isNot(contains('.update(')));
      expect(source, isNot(contains('.delete(')));
    }
  });

  test('Receipt Line Builder has no reverse recovery dependency', () {
    final builderFiles =
        Directory('lib/receipt_line_builder').listSync(recursive: true);

    for (final entry in builderFiles.whereType<File>()) {
      expect(
        entry.readAsStringSync(),
        isNot(contains('orphan_line_recovery')),
        reason: entry.path,
      );
    }
  });
}
