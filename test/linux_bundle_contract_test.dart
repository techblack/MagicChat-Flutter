import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux bundle carries the Ayatana IDO runtime library', () async {
    final source = await File('linux/CMakeLists.txt').readAsString();

    expect(source, contains('libayatana-ido3-0.4.so.0'));
    expect(source, contains('AYATANA_IDO_RUNTIME_REALPATH'));
    expect(source, contains('RENAME "libayatana-ido3-0.4.so.0"'));
  });
}
