import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/cli.dart';

/// The release version is declared in five places that nothing else links:
/// this test fails when any one of them is bumped alone.
void main() {
  test('every version field matches Cli.appVersion', () {
    expect(_pubspecVersion(), Cli.appVersion);
    expect(_pkgbuildVersion('packaging/arch/PKGBUILD'), Cli.appVersion);
    expect(
      _pkgbuildVersion('packaging/aur/trickster-bin/PKGBUILD'),
      Cli.appVersion,
    );
    expect(_nativeVersion(), Cli.appVersion);
  });
}

String _pubspecVersion() {
  final line = File(
    'pubspec.yaml',
  ).readAsLinesSync().firstWhere((line) => line.startsWith('version:'));
  return line.split(':').last.trim();
}

String _pkgbuildVersion(String path) {
  final line = File(
    path,
  ).readAsLinesSync().firstWhere((line) => line.startsWith('pkgver='));
  return line.split('=').last.trim();
}

String _nativeVersion() {
  final source = File('linux/runner/my_application.cc').readAsStringSync();
  final match = RegExp(
    r'"trickster ([0-9]+\.[0-9]+\.[0-9]+)\\n"',
  ).firstMatch(source);
  expect(match, isNotNull, reason: 'native --version print not found');
  return match!.group(1)!;
}
