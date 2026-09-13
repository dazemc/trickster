import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/cli.dart';

/// Man pages escape hyphens as `\-`; compare against plain text.
String _roff(String path) =>
    File(path).readAsStringSync().replaceAll(r'\-', '-');

Iterable<String> _flags(String usage) =>
    RegExp(r'--[a-z][a-z-]*').allMatches(usage).map((match) => match.group(0)!);

void main() {
  test('trickster.1 documents every flag in --help', () {
    final man = _roff('packaging/man/trickster.1');
    for (final flag in {..._flags(Cli.usage), '-h'}) {
      expect(man, contains(flag), reason: '$flag missing from trickster.1');
    }
  });

  test('tricksterctl.1 documents every command and flag in --help', () {
    final man = _roff('packaging/man/tricksterctl.1');
    for (final flag in {..._flags(Cli.ctlUsage), '-h', '-v'}) {
      expect(man, contains(flag), reason: '$flag missing from tricksterctl.1');
    }
    for (final command in ['status', 'version', 'reload']) {
      expect(man, contains(command), reason: '$command missing');
    }
  });
}
