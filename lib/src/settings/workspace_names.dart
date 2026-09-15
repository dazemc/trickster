import 'package:trickster/src/platform/control_socket.dart';

/// The live workspace names the running bar reports, sorted and unique.
///
/// The settings process never samples the compositor itself; it asks the bar
/// over the control socket. An unreachable bar resolves to an empty list so
/// the mapping editor still allows typing a name by hand.
Future<List<String>> fetchWorkspaceNames({String? socketPath}) async {
  try {
    final reply = await controlRequest(const <String, Object?>{
      'command': 'status',
    }, socketPath: socketPath);
    if (reply['ok'] != true) {
      return const <String>[];
    }
    final state = reply['state'];
    if (state is! Map) {
      return const <String>[];
    }
    final workspaces = state['workspaces'];
    if (workspaces is! Map) {
      return const <String>[];
    }
    final list = workspaces['workspaces'];
    if (list is! List) {
      return const <String>[];
    }
    final names = <String>{};
    for (final entry in list) {
      if (entry is Map && entry['name'] is String) {
        final name = (entry['name'] as String).trim();
        if (name.isNotEmpty) {
          names.add(name);
        }
      }
    }
    return names.toList()..sort();
  } on Object {
    return const <String>[];
  }
}
