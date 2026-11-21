import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The network module reads procfs/sysfs directly. A command-line helper would
/// add a process, a parse surface, and a dependency the bar cannot guarantee.
void main() {
  test('the network module never spawns a process', () {
    const files = [
      'lib/src/services/network.dart',
      'lib/src/state/network_bloc.dart',
      'lib/src/bar/network.dart',
    ];
    const forbidden = [
      'Process.run',
      'Process.start',
      'Process.runSync',
      'Process.startSync',
      'nmcli',
      "'iw'",
      '"iw"',
    ];
    final offenders = <String>[];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final token in forbidden) {
        if (source.contains(token)) {
          offenders.add('$path: $token');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'read /proc and /sys; never spawn nmcli, iw, or ethtool',
    );
  });
}
