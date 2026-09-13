import 'dart:convert';
import 'dart:io';

import 'package:trickster/src/cli.dart';
import 'package:trickster/src/platform/control_socket.dart';

/// Short-lived client for the bar's control socket. Never a second UI.
Future<void> main(List<String> args) async {
  final command = args.isEmpty ? 'status' : args.first;
  if (command == '--version' || command == '-v') {
    stdout.writeln('tricksterctl ${Cli.appVersion}');
    return;
  }
  try {
    switch (command) {
      case 'status':
        final reply = await controlRequest(<String, Object?>{
          'command': 'status',
        });
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(reply));
      case 'reload':
        final reply = await controlRequest(<String, Object?>{
          'command': 'reload',
        });
        if (reply['ok'] == true) {
          stdout.writeln('ok');
        } else {
          stderr.writeln('tricksterctl: ${reply['error'] ?? 'reload failed'}');
          exitCode = 1;
        }
      case 'version':
        final reply = await controlRequest(<String, Object?>{
          'command': 'version',
        });
        final version = reply['version'];
        if (reply['ok'] == true && version is String) {
          stdout.writeln(version);
        } else {
          stderr.writeln('tricksterctl: ${reply['error'] ?? 'unknown error'}');
          exitCode = 1;
        }
      default:
        stderr.writeln('usage: tricksterctl status|version|reload');
        exitCode = 64;
    }
  } on ControlSocketException catch (error) {
    stderr.writeln('tricksterctl: ${error.message}');
    exitCode = 1;
  }
}
