import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

class Workspace extends Equatable {
  const Workspace({
    required this.id,
    required this.name,
    this.focused = false,
    this.urgent = false,
    this.occupied = false,
  });

  final String id;
  final String name;
  final bool focused;
  final bool urgent;
  final bool occupied;

  @override
  List<Object?> get props => [id, name, focused, urgent, occupied];

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'focused': focused,
    'urgent': urgent,
    'occupied': occupied,
  };

  static Workspace fromJson(Map<String, dynamic> json) => Workspace(
    id: '${json['id']}',
    name: '${json['name']}',
    focused: (json['focused'] as bool?) ?? false,
    urgent: (json['urgent'] as bool?) ?? false,
    occupied: (json['occupied'] as bool?) ?? false,
  );
}

List<Map<String, Object?>> workspacesToJson(List<Workspace> workspaces) =>
    workspaces.map((workspace) => workspace.toJson()).toList(growable: false);

List<Workspace> workspacesFromJson(List<dynamic> json) => json
    .whereType<Map<String, dynamic>>()
    .map(Workspace.fromJson)
    .toList(growable: false);

/// Bloc state for the workspace list. A bare `List` compares by identity,
/// so the wrapper exists to give the bloc value semantics — and a JSON
/// shape for the future `tricksterctl status` dump.
class WorkspacesState extends Equatable {
  const WorkspacesState([this.workspaces = const []]);

  final List<Workspace> workspaces;

  // Spread: Equatable compares props element-wise, so spreading gives deep
  // equality over the list (each Workspace is itself Equatable).
  @override
  List<Object?> get props => [...workspaces];

  Map<String, Object?> toJson() => {
    'workspaces': workspacesToJson(workspaces),
  };

  static WorkspacesState fromJson(Map<String, dynamic> json) =>
      WorkspacesState(
        workspacesFromJson((json['workspaces'] as List?) ?? const []),
      );
}

/// Orders workspaces for the rail: numeric ids first in numeric order, then
/// named ids lexicographically. Compositor replies are not ordered — Hyprland
/// iterates an unordered workspace map — so the rail must not trust them.
int compareWorkspaces(Workspace left, Workspace right) {
  final leftNumber = int.tryParse(left.id);
  final rightNumber = int.tryParse(right.id);
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }
  if (leftNumber != null) {
    return -1;
  }
  if (rightNumber != null) {
    return 1;
  }
  return left.id.compareTo(right.id);
}

List<Workspace> sortedWorkspaces(List<Workspace> workspaces) =>
    [...workspaces]..sort(compareWorkspaces);

abstract class WorkspaceBackend {
  Stream<List<Workspace>> get snapshots;
  Future<void> start();
  Future<void> dispose();

  /// Focuses [workspace] through the compositor. Backends override this when
  /// their compositor can switch workspaces; the default cannot.
  Future<bool> focusWorkspace(Workspace workspace) async => false;
}

class WorkspaceMonitor {
  WorkspaceMonitor({WorkspaceBackend? backend})
    : _backend = backend ?? _detect();

  // Detected in the constructor, not in start(): WorkspacesBloc subscribes
  // to snapshots before starting the monitor, and a backend created in
  // start() would leave that subscription attached to an empty stream —
  // the initial refresh (and every later one) unheard.
  WorkspaceBackend? _backend;

  Stream<List<Workspace>> get snapshots =>
      _backend?.snapshots ?? const Stream.empty();

  Future<void> start() async {
    await _backend?.start();
  }

  Future<void> dispose() async {
    await _backend?.dispose();
    _backend = null;
  }

  Future<bool> focusWorkspace(Workspace workspace) async {
    return await _backend?.focusWorkspace(workspace) ?? false;
  }

  static WorkspaceBackend? _detect() {
    if (Platform.environment.containsKey('HYPRLAND_INSTANCE_SIGNATURE')) {
      return HyprlandWorkspaces();
    }
    if (Platform.environment.containsKey('SWAYSOCK')) {
      return SwayWorkspaces();
    }
    if (Platform.environment.containsKey('NIRI_SOCKET')) {
      return NiriWorkspaces();
    }
    return null;
  }
}

class HyprlandWorkspaces extends WorkspaceBackend {
  HyprlandWorkspaces({String? socketDir}) : _socketDir = socketDir ?? _dirFromEnvironment;

  static String? get _dirFromEnvironment {
    final signature = Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'];
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (signature == null || runtime == null) {
      return null;
    }
    return '$runtime/hypr/$signature';
  }

  /// Cap on a single `j/*` reply. Replies are ~1 KiB; the cap only bounds a
  /// runaway socket, never real data.
  static const _maxReplyBytes = 1 << 20;

  static const _replyTimeout = Duration(seconds: 5);

  static const _reconnectDelayBase = Duration(milliseconds: 500);

  static const _reconnectDelayMax = Duration(seconds: 5);

  final String? _socketDir;
  Socket? _events;
  Timer? _reconnect;
  Duration _reconnectDelay = _reconnectDelayBase;
  var _generation = 0;
  final _controller = StreamController<List<Workspace>>.broadcast();

  @override
  Stream<List<Workspace>> get snapshots => _controller.stream;

  @override
  Future<void> start() async {
    await _refresh();
    _connectEvents();
  }

  void _connectEvents() {
    final dir = _socketDir;
    if (dir == null) {
      return;
    }
    final generation = _generation;
    unawaited(_dialEvents(dir, generation));
  }

  Future<void> _dialEvents(String dir, int generation) async {
    Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress('$dir/.socket2.sock', type: InternetAddressType.unix),
        0,
      );
    } on Object {
      _scheduleReconnect(generation);
      return;
    }
    if (generation != _generation) {
      await socket.close();
      return;
    }
    _events = socket;
    _reconnectDelay = _reconnectDelayBase;
    unawaited(_refresh());
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        // socket2 sends newline-terminated `event>>payload` lines; a chunk
        // boundary can split them, so reassemble before matching.
        buffer.write(utf8.decode(data, allowMalformed: true));
        var text = buffer.toString();
        var newline = text.indexOf('\n');
        while (newline != -1) {
          _handleEvent(text.substring(0, newline));
          text = text.substring(newline + 1);
          newline = text.indexOf('\n');
        }
        buffer
          ..clear()
          ..write(text);
      },
      onError: (_) {},
      onDone: () => _scheduleReconnect(generation),
    );
  }

  /// Re-dials the event socket after a drop or a refused connection, with a
  /// capped backoff so a compositor restart recovers without hot-looping.
  void _scheduleReconnect(int generation) {
    if (_generation != generation) {
      return;
    }
    _generation += 1;
    _events = null;
    _reconnect?.cancel();
    _reconnect = Timer(_reconnectDelay, () {
      _reconnect = null;
      if (_generation == generation + 1) {
        _connectEvents();
      }
    });
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectDelayMax ? _reconnectDelayMax : next;
  }

  void _handleEvent(String line) {
    if (line.contains('workspace') ||
        line.contains('focusedmon') ||
        line.startsWith('urgent')) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final dir = _socketDir;
    if (dir == null) {
      return;
    }
    try {
      final replies = await _onWorker(const [
        'j/workspaces',
        'j/activeworkspace',
        'j/clients',
      ], dir);
      final workspacesJson = replies[0];
      if (workspacesJson is! List) {
        return;
      }
      // `j/workspaces` carries no focused flag — join the active workspace
      // in the same refresh. `j/clients` supplies urgency the same way:
      // no per-workspace urgency exists in the workspace JSON.
      final activeJson = replies[1];
      final activeId = activeJson is Map ? '${activeJson['id']}' : null;
      final clientsJson = replies[2];
      final urgentIds = <String>{};
      if (clientsJson is List) {
        for (final client in clientsJson) {
          if (client is Map && client['urgent'] == true) {
            final workspace = client['workspace'];
            if (workspace is Map && workspace['id'] != null) {
              urgentIds.add('${workspace['id']}');
            }
          }
        }
      }
      final workspaces = <Workspace>[];
      for (final entry in workspacesJson) {
        if (entry is! Map) {
          continue;
        }
        final id = '${entry['id']}';
        final windows = entry['windows'];
        workspaces.add(
          Workspace(
            id: id,
            name: '${entry['name'] ?? entry['id']}',
            focused: activeId != null
                ? id == activeId
                : entry['focused'] == true,
            urgent: urgentIds.contains(id),
            occupied: windows is num && windows > 0,
          ),
        );
      }
      _controller.add(workspaces);
    } on Object {
      return;
    }
  }

  /// Runs the `j/*` queries on a worker isolate and returns the decoded
  /// documents in order.
  ///
  /// The compositor serves `.socket.sock` on its main loop: Hyprland accepts
  /// a connection and blocks in `poll()` for up to five seconds until the
  /// command arrives (see `hyprCtlFDTick`). On the UI isolate, connect and
  /// write do not share a turn with the engine's compositor waits — during
  /// startup the platform thread can block in a Wayland roundtrip before the
  /// queued command is flushed, so the compositor waits on the connection
  /// while the client waits on the compositor, and both give up on timeout:
  /// a five second freeze and a torn-down layer surface. A worker isolate
  /// has no other work, so its connect is followed by the write immediately
  /// and the compositor never sees a silent connection.
  static Future<List<Object?>> _onWorker(List<String> commands, String dir) {
    return Isolate.run(() => _queryAll(commands, dir));
  }

  static Future<List<Object?>> _queryAll(
    List<String> commands,
    String dir,
  ) async {
    final replies = <Object?>[];
    for (final command in commands) {
      replies.add(await _query(command, dir));
    }
    return replies;
  }

  /// One `j/*` query with a bounded read. Some Hyprland versions keep the
  /// request connection open after the reply, so reading until socket-done
  /// hangs forever — instead return as soon as the accumulated bytes parse
  /// as a complete JSON document. The byte cap and timeout bound the cases
  /// where no complete document ever arrives. Returns null when the query
  /// fails, keeping the previous snapshot.
  ///
  /// A transport failure (refused connection, reset mid-write) is retried
  /// once on a fresh connection after a short settle delay: the compositor
  /// serves IPC on its main loop, and a connection opened while it is still
  /// tearing down the previous one can be refused.
  static Future<Object?> _query(String command, String dir) async {
    try {
      return await _attemptQuery(command, dir);
    } on SocketException {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        return await _attemptQuery(command, dir);
      } on Object {
        return null;
      }
    } on Object {
      return null;
    }
  }

  static Future<Object?> _attemptQuery(String command, String dir) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress('$dir/.socket.sock', type: InternetAddressType.unix),
        0,
      );
      socket.add(utf8.encode(command));
      final buffer = BytesBuilder();
      await for (final chunk in socket.timeout(_replyTimeout)) {
        buffer.add(chunk);
        if (buffer.length > _maxReplyBytes) {
          return null;
        }
        try {
          return jsonDecode(utf8.decode(buffer.toBytes()));
        } on FormatException {
          continue; // Incomplete document (or split multibyte rune).
        }
      }
      return null; // EOF before a complete document.
    } finally {
      await socket?.close();
    }
  }

  @override
  Future<bool> focusWorkspace(Workspace workspace) async {
    final dir = _socketDir;
    if (dir == null) {
      return false;
    }
    final name = workspace.name;
    final number = int.tryParse(workspace.id);
    final luaSelector = number != null && number > 0
        ? '$number'
        : '"${_escapeLua(name)}"';
    try {
      return await Isolate.run(() async {
        // Hyprland 0.56 made dispatch evaluate Lua (`hl.dsp.*`); older
        // releases use the classic `workspace` dispatcher. Try the classic
        // form first and fall back when the reply reports the Lua error.
        if (await _sendCommand('dispatch workspace $name', dir) == 'ok') {
          return true;
        }
        final lua =
            'dispatch hl.dsp.focus({ workspace = $luaSelector })';
        return await _sendCommand(lua, dir) == 'ok';
      });
    } on Object {
      return false;
    }
  }

  static String _escapeLua(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  /// Sends one command on a fresh connection and waits for the compositor's
  /// reply. Like the `j/*` queries, this runs on a worker isolate: the
  /// compositor serves `.socket.sock` on its main loop and accepts a
  /// connection only when the command follows immediately.
  static Future<String?> _sendCommand(String command, String dir) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress('$dir/.socket.sock', type: InternetAddressType.unix),
        0,
      );
      socket.add(utf8.encode(command));
      final buffer = BytesBuilder();
      await for (final chunk in socket.timeout(_replyTimeout)) {
        buffer.add(chunk);
        final reply = utf8.decode(
          buffer.toBytes(),
          allowMalformed: true,
        ).trim();
        if (reply == 'ok' || reply.startsWith('error:')) {
          return reply;
        }
        if (buffer.length > _maxReplyBytes) {
          return null;
        }
      }
      final reply = utf8.decode(buffer.toBytes(), allowMalformed: true).trim();
      return reply.isEmpty ? null : reply;
    } on Object {
      return null;
    } finally {
      await socket?.close();
    }
  }

  @override
  Future<void> dispose() async {
    _generation += 1;
    _reconnect?.cancel();
    _reconnect = null;
    await _events?.close();
    _events = null;
    await _controller.close();
  }
}

class SwayWorkspaces extends WorkspaceBackend {
  SwayWorkspaces({String? socketPath}) : _socketPath = socketPath;

  /// Cap on a single command reply; the cap only bounds a runaway socket,
  /// never real data.
  static const _maxReplyBytes = 1 << 20;

  static const _replyTimeout = Duration(seconds: 5);

  /// Sway sets bit 31 on event types; workspace events carry type 3.
  static const _workspaceEventType = 0x80000003;

  static const _reconnectDelayBase = Duration(milliseconds: 500);

  static const _reconnectDelayMax = Duration(seconds: 5);

  final String? _socketPath;
  Socket? _socket;
  Timer? _reconnect;
  Duration _reconnectDelay = _reconnectDelayBase;
  var _generation = 0;
  final _buffer = <int>[];
  final _controller = StreamController<List<Workspace>>.broadcast();

  @override
  Stream<List<Workspace>> get snapshots => _controller.stream;

  String? get _path => _socketPath ?? Platform.environment['SWAYSOCK'];

  @override
  Future<void> start() async {
    final path = _path;
    if (path == null) {
      return;
    }
    await _dial(path, _generation);
  }

  Future<void> _dial(String path, int generation) async {
    Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
    } on Object {
      _scheduleReconnect(generation);
      return;
    }
    if (generation != _generation) {
      await socket.close();
      return;
    }
    _socket = socket;
    _reconnectDelay = _reconnectDelayBase;
    _buffer.clear();
    socket.listen(
      _onData,
      onError: (_) {},
      onDone: () => _scheduleReconnect(generation),
    );
    _subscribe();
    _request(1);
  }

  /// Re-dials after a drop or a refused connection, with a capped backoff so
  /// a compositor restart recovers without hot-looping.
  void _scheduleReconnect(int generation) {
    if (_generation != generation) {
      return;
    }
    _generation += 1;
    _socket = null;
    _reconnect?.cancel();
    _reconnect = Timer(_reconnectDelay, () {
      _reconnect = null;
      if (_generation == generation + 1) {
        final path = _path;
        if (path != null) {
          unawaited(_dial(path, _generation));
        }
      }
    });
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectDelayMax ? _reconnectDelayMax : next;
  }

  /// Focuses a workspace over a one-shot command connection — the same
  /// pattern `swaymsg` uses for single commands — keeping the event
  /// connection dedicated to its subscription.
  @override
  Future<bool> focusWorkspace(Workspace workspace) async {
    final path = _path;
    if (path == null) {
      return false;
    }
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      socket.add(_frame(0, utf8.encode('workspace ${workspace.name}')));
      final buffer = BytesBuilder();
      await for (final chunk in socket.timeout(_replyTimeout)) {
        buffer.add(chunk);
        final reply = _decodeReply(buffer.toBytes());
        if (reply != null) {
          return reply['success'] == true;
        }
        if (buffer.length > _maxReplyBytes) {
          return false;
        }
      }
      return false;
    } on Object {
      return false;
    } finally {
      await socket?.close();
    }
  }

  static Map<String, dynamic>? _decodeReply(List<int> bytes) {
    if (bytes.length < 14) {
      return null;
    }
    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    final length = view.getUint32(6, Endian.little);
    if (bytes.length < 14 + length) {
      return null;
    }
    final decoded = jsonDecode(utf8.decode(bytes.sublist(14, 14 + length)));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  void _subscribe() {
    _socket?.add(_frame(2, utf8.encode('["workspace"]')));
  }

  void _request(int type) {
    _socket?.add(_frame(type, Uint8List(0)));
  }

  /// Reassembles `i3-ipc` frames across chunk boundaries and dispatches them:
  /// the type-1 reply carries the workspace list, workspace events request a
  /// fresh one. Nothing else re-requests, so a healthy socket is quiet
  /// between events.
  void _onData(Uint8List data) {
    _buffer.addAll(data);
    var consumed = 0;
    while (_buffer.length - consumed >= 14) {
      if (!_hasMagic(_buffer, consumed)) {
        _buffer.clear();
        return;
      }
      final length = _readUint32(_buffer, consumed + 6);
      if (_buffer.length - consumed < 14 + length) {
        break;
      }
      final type = _readUint32(_buffer, consumed + 10);
      final payload = _buffer.sublist(consumed + 14, consumed + 14 + length);
      consumed += 14 + length;
      _handleFrame(type, payload);
    }
    if (consumed > 0) {
      _buffer.removeRange(0, consumed);
    }
    if (_buffer.length > _maxReplyBytes) {
      _buffer.clear();
    }
  }

  void _handleFrame(int type, List<int> payload) {
    if (type == 1) {
      _emitWorkspaces(payload);
      return;
    }
    if (type == _workspaceEventType) {
      _request(1);
    }
  }

  void _emitWorkspaces(List<int> payload) {
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! List) {
        return;
      }
      final workspaces = <Workspace>[];
      for (final entry in decoded) {
        if (entry is! Map) {
          continue;
        }
        final number = entry['num'];
        final name = '${entry['name'] ?? number}';
        workspaces.add(
          Workspace(
            id: number is int && number >= 0 ? '$number' : name,
            name: name,
            focused: entry['focused'] == true,
            urgent: entry['urgent'] == true,
          ),
        );
      }
      _controller.add(workspaces);
    } on Object {
      return;
    }
  }

  static bool _hasMagic(List<int> bytes, int offset) {
    const magic = 'i3-ipc';
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  static int _readUint32(List<int> bytes, int offset) =>
      bytes[offset] |
      bytes[offset + 1] << 8 |
      bytes[offset + 2] << 16 |
      bytes[offset + 3] << 24;

  Uint8List _frame(int type, List<int> payload) {
    final header = Uint8List(14);
    header.setAll(0, utf8.encode('i3-ipc'));
    final view = ByteData.sublistView(header);
    view.setUint32(6, payload.length, Endian.little);
    view.setUint32(10, type, Endian.little);
    return Uint8List.fromList([...header, ...payload]);
  }

  @override
  Future<void> dispose() async {
    _generation += 1;
    _reconnect?.cancel();
    _reconnect = null;
    await _socket?.close();
    _socket = null;
    _buffer.clear();
    await _controller.close();
  }
}

class NiriWorkspaces extends WorkspaceBackend {
  NiriWorkspaces({String? socketPath}) : _socketPath = socketPath;

  /// Cap on a single action reply; the cap only bounds a runaway socket,
  /// never real data.
  static const _maxReplyBytes = 1 << 20;

  static const _replyTimeout = Duration(seconds: 5);

  static const _reconnectDelayBase = Duration(milliseconds: 500);

  static const _reconnectDelayMax = Duration(seconds: 5);

  final String? _socketPath;
  Socket? _socket;
  Timer? _reconnect;
  Duration _reconnectDelay = _reconnectDelayBase;
  var _generation = 0;
  final _controller = StreamController<List<Workspace>>.broadcast();

  @override
  Stream<List<Workspace>> get snapshots => _controller.stream;

  String? get _path => _socketPath ?? Platform.environment['NIRI_SOCKET'];

  @override
  Future<void> start() async {
    final path = _path;
    if (path == null) {
      return;
    }
    await _dial(path, _generation);
  }

  Future<void> _dial(String path, int generation) async {
    Socket socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
    } on Object {
      _scheduleReconnect(generation);
      return;
    }
    if (generation != _generation) {
      await socket.close();
      return;
    }
    _socket = socket;
    _reconnectDelay = _reconnectDelayBase;
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        buffer.write(utf8.decode(data));
        var text = buffer.toString();
        var newline = text.indexOf('\n');
        while (newline != -1) {
          final line = text.substring(0, newline);
          text = text.substring(newline + 1);
          _handle(line);
          newline = text.indexOf('\n');
        }
        buffer
          ..clear()
          ..write(text);
      },
      onError: (_) {},
      onDone: () => _scheduleReconnect(generation),
    );
    socket.add(utf8.encode('${jsonEncode({'EventStream': null})}\n'));
  }

  /// Re-dials after a drop or a refused connection, with a capped backoff so
  /// a compositor restart recovers without hot-looping. The event stream
  /// replays the full workspace state on connect, so no extra refresh is
  /// needed.
  void _scheduleReconnect(int generation) {
    if (_generation != generation) {
      return;
    }
    _generation += 1;
    _socket = null;
    _reconnect?.cancel();
    _reconnect = Timer(_reconnectDelay, () {
      _reconnect = null;
      if (_generation == generation + 1) {
        final path = _path;
        if (path != null) {
          unawaited(_dial(path, _generation));
        }
      }
    });
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectDelayMax ? _reconnectDelayMax : next;
  }

  /// Focuses a workspace over a one-shot action connection — the same
  /// pattern `niri msg` uses — keeping the event stream connection dedicated
  /// to its subscription.
  @override
  Future<bool> focusWorkspace(Workspace workspace) async {
    final path = _path;
    if (path == null) {
      return false;
    }
    final number = int.tryParse(workspace.id);
    final reference = number != null
        ? '{"Id":$number}'
        : '{"Name":${jsonEncode(workspace.name)}}';
    final request = '{"Action":{"FocusWorkspace":{"reference":$reference}}}\n';
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      socket.add(utf8.encode(request));
      final buffer = BytesBuilder();
      await for (final chunk in socket.timeout(_replyTimeout)) {
        buffer.add(chunk);
        if (buffer.length > _maxReplyBytes) {
          return false;
        }
        try {
          final decoded = jsonDecode(utf8.decode(buffer.toBytes()).trim());
          return decoded is Map && decoded.containsKey('Ok');
        } on FormatException {
          continue; // Incomplete document (or split multibyte rune).
        }
      }
      return false;
    } on Object {
      return false;
    } finally {
      await socket?.close();
    }
  }

  void _handle(String line) {
    if (line.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return;
      }
      final event = decoded['WorkspacesChanged'] ?? decoded['Workspaces'];
      if (event is! Map) {
        return;
      }
      final list = event['workspaces'];
      if (list is! List) {
        return;
      }
      final workspaces = <Workspace>[];
      for (final entry in list) {
        if (entry is! Map) {
          continue;
        }
        workspaces.add(
          Workspace(
            id: '${entry['id'] ?? entry['idx']}',
            name: '${entry['name'] ?? entry['idx'] ?? entry['id']}',
            focused: entry['is_focused'] == true || entry['focused'] == true,
            urgent: entry['is_urgent'] == true,
            occupied: entry['active_window_id'] != null,
          ),
        );
      }
      _controller.add(workspaces);
    } on Object {
      return;
    }
  }

  @override
  Future<void> dispose() async {
    _generation += 1;
    _reconnect?.cancel();
    _reconnect = null;
    await _socket?.close();
    _socket = null;
    await _controller.close();
  }
}
