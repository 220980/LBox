import 'dart:convert';
import 'dart:io';

import 'package:fl_tty/fl_tty.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the library `hook/build.dart` builds, which is the point: a pty that
/// starts is a library that was built, bundled and found.
void main() {
  test('a pty runs a command and hands back what it printed', () async {
    final pty = Pty.start('/bin/sh', arguments: ['-c', 'printf hello']);
    final out = await pty.output.cast<List<int>>().transform(utf8.decoder).join();
    expect(out, contains('hello'));
    expect(await pty.exitCode, 0);
  }, skip: Platform.isWindows);
}
