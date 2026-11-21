import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// The selected keyboard's active layout, as reported by the compositor.
class KeyboardLayoutState extends Equatable {
  const KeyboardLayoutState({
    this.available = false,
    this.backend,
    this.active,
    this.index,
    this.names = const [],
  });

  final bool available;
  final String? backend;

  /// Short active layout token, uppercase (`US`, `RU`), or null.
  final String? active;

  /// Index into [names] reported by the compositor.
  final int? index;

  /// Layout tokens in compositor order (`['us', 'ru']`).
  final List<String> names;

  bool get hasLayout => available && active != null && active!.isNotEmpty;

  @override
  List<Object?> get props => [available, backend, active, index, names];

  Map<String, Object?> toJson() => {
    'available': available,
    'backend': backend,
    'active': active,
    'index': index,
    'names': names,
  };

  static KeyboardLayoutState fromJson(Map<String, dynamic> json) =>
      KeyboardLayoutState(
        available: json['available'] == true,
        backend: json['backend'] as String?,
        active: json['active'] as String?,
        index: (json['index'] as num?)?.toInt(),
        names: [
          for (final name in json['names'] as List<dynamic>? ?? const [])
            '$name',
        ],
      );
}

/// Parses the `j/devices` document. The main keyboard wins; when none is
/// marked main, the first keyboard in compositor order is used. Other
/// keyboards are ignored: their layouts can differ, and the bar has one
/// global keyboard-layout pill.
@visibleForTesting
KeyboardLayoutState? parseHyprlandDevices(Object? json) {
  if (json is! Map<String, dynamic>) {
    return null;
  }
  final keyboards = json['keyboards'];
  if (keyboards is! List || keyboards.isEmpty) {
    return const KeyboardLayoutState(backend: 'hyprland');
  }
  Map<String, dynamic>? selected;
  for (final keyboard in keyboards) {
    if (keyboard is Map<String, dynamic> && keyboard['main'] == true) {
      selected = keyboard;
      break;
    }
  }
  selected ??= keyboards.whereType<Map<String, dynamic>>().firstOrNull;
  if (selected == null) {
    return const KeyboardLayoutState(backend: 'hyprland');
  }
  final layout = selected['layout'];
  final names = layout is String
      ? [
          for (final name in layout.split(','))
            if (name.trim().isNotEmpty) name.trim(),
        ]
      : const <String>[];
  final rawIndex = selected['active_layout_index'];
  final index = rawIndex is num ? rawIndex.toInt() : (names.isEmpty ? null : 0);
  final active = index != null && index >= 0 && index < names.length
      ? names[index].toUpperCase()
      : (names.isEmpty ? null : names.first.toUpperCase());
  return KeyboardLayoutState(
    available: true,
    backend: 'hyprland',
    active: active,
    index: index,
    names: names,
  );
}

/// One keyboard-layout backend.
///
/// Multi-keyboard rule: Hyprland uses the keyboard marked `main` (otherwise
/// the first), Sway uses the first keyboard that publishes layout data
/// (otherwise the first), and niri reports one configured layout set. The bar
/// has one global pill, so other keyboards are ignored.
abstract interface class KeyboardLayoutBackend {
  Stream<KeyboardLayoutState> get snapshots;

  Future<void> start();

  Future<void> dispose();
}

/// Hyprland keyboard layout over `.socket.sock` (`j/devices`) and
/// `.socket2.sock` (`activelayout` events).
///
/// The initial state is queried once; layout changes are event-driven and
/// coalesced into one re-query. There is no polling and no idle pause. A dead
/// event socket reconnects with capped exponential backoff.
class HyprlandKeyboardLayout implements KeyboardLayoutBackend {
  HyprlandKeyboardLayout({String? socketDir})
    : _socketDir = socketDir ?? _dirFromEnvironment;

  static String? get _dirFromEnvironment {
    final signature = Platform.environment['HYPRLAND_INSTANCE_SIGNATURE'];
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (signature == null || runtime == null) {
      return null;
    }
    return '$runtime/hypr/$signature';
  }

  static const _maxReplyBytes = 1 << 20;
  static const _replyTimeout = Duration(seconds: 5);
  static const _reconnectDelayBase = Duration(milliseconds: 500);
  static const _reconnectDelayMax = Duration(seconds: 5);
  static const _eventDebounce = Duration(milliseconds: 32);

  final String? _socketDir;
  Socket? _events;
  Timer? _reconnect;
  Timer? _refreshDebounce;
  Duration _reconnectDelay = _reconnectDelayBase;
  var _generation = 0;
  var _refreshing = false;
  var _refreshAgain = false;
  var _running = false;
  var _disposed = false;
  KeyboardLayoutState? _last;
  final _controller = StreamController<KeyboardLayoutState>.broadcast();

  @override
  Stream<KeyboardLayoutState> get snapshots => _controller.stream;

  @visibleForTesting
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    if (_running || _disposed) {
      return;
    }
    _running = true;
    await _refresh();
    if (_running && !_disposed) {
      _connectEvents();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _running = false;
    _generation += 1;
    _reconnect?.cancel();
    _reconnect = null;
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    final events = _events;
    _events = null;
    await events?.close();
    await _controller.close();
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
    if (generation != _generation || _disposed || !_running) {
      await socket.close();
      return;
    }
    _events = socket;
    _reconnectDelay = _reconnectDelayBase;
    unawaited(_refresh());
    final buffer = StringBuffer();
    socket.listen(
      (data) {
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

  void _scheduleReconnect(int generation) {
    if (_disposed || !_running || generation != _generation) {
      return;
    }
    _generation += 1;
    _events = null;
    _reconnect?.cancel();
    _reconnect = Timer(_reconnectDelay, () {
      _reconnect = null;
      if (!_disposed && _running) {
        _connectEvents();
      }
    });
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectDelayMax ? _reconnectDelayMax : next;
  }

  void _handleEvent(String line) {
    if (!line.startsWith('activelayout>>')) {
      return;
    }
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_eventDebounce, () {
      _refreshDebounce = null;
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        await _refreshOnce();
      } while (_refreshAgain);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshOnce() async {
    final dir = _socketDir;
    if (dir == null) {
      _emit(const KeyboardLayoutState(backend: 'hyprland'));
      return;
    }
    final state = await Isolate.run(() => _queryDevices(dir));
    if (!_running || _disposed || _controller.isClosed) {
      return;
    }
    if (state == null) {
      if (_last == null) {
        _emit(const KeyboardLayoutState(backend: 'hyprland'));
      }
      return;
    }
    _emit(state);
  }

  void _emit(KeyboardLayoutState state) {
    if (_last == state || _controller.isClosed) {
      return;
    }
    _last = state;
    _controller.add(state);
  }
}

Future<KeyboardLayoutState?> _queryDevices(String dir) async {
  Socket? socket;
  StreamSubscription<List<int>>? subscription;
  try {
    socket = await Socket.connect(
      InternetAddress('$dir/.socket.sock', type: InternetAddressType.unix),
      0,
    );
    final buffer = BytesBuilder();
    final done = Completer<KeyboardLayoutState?>();
    subscription = socket.listen(
      (data) {
        buffer.add(data);
        if (buffer.length > HyprlandKeyboardLayout._maxReplyBytes) {
          if (!done.isCompleted) {
            done.complete(null);
          }
          return;
        }
        try {
          final decoded = jsonDecode(utf8.decode(buffer.toBytes()));
          final state = parseHyprlandDevices(decoded);
          if (!done.isCompleted) {
            done.complete(state);
          }
        } on FormatException {
          // A split JSON chunk; wait for more bytes.
        }
      },
      onError: (_) {
        if (!done.isCompleted) {
          done.complete(null);
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete(null);
        }
      },
    );
    socket.add(utf8.encode('j/devices'));
    return await done.future.timeout(
      HyprlandKeyboardLayout._replyTimeout,
      onTimeout: () => null,
    );
  } on Object {
    return null;
  } finally {
    await subscription?.cancel();
    socket?.destroy();
  }
}

/// Auto-detects the compositor backend in the same order as the workspace
/// service: Hyprland, then Sway, then niri. A missing environment or runtime
/// directory yields null, and the bloc keeps an unavailable state without
/// opening sockets.
KeyboardLayoutBackend? detectKeyboardLayoutBackend({
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final runtime = env['XDG_RUNTIME_DIR'];
  if (env['HYPRLAND_INSTANCE_SIGNATURE'] != null && runtime != null) {
    return HyprlandKeyboardLayout();
  }
  if (env['SWAYSOCK'] != null) {
    return SwayKeyboardLayout();
  }
  if (env['NIRI_SOCKET'] != null) {
    return NiriKeyboardLayout();
  }
  return null;
}

/// Shorts a layout name to the token shown in the pill: `(US)` from
/// `English (US)`, `US` from `us`, otherwise the uppercase name.
String? shortLayoutCode(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final match = RegExp(r'\(([^)]+)\)\s*$').firstMatch(trimmed);
  if (match != null) {
    return match.group(1)!.trim().toUpperCase();
  }
  final alias = _layoutAliases[trimmed.toLowerCase()];
  if (alias != null) {
    return alias;
  }
  final first = trimmed.split(RegExp(r'[\s,]+')).first;
  return first.isEmpty ? null : first.toUpperCase();
}

const _layoutAliases = <String, String>{
  'english': 'EN',
  'russian': 'RU',
  'german': 'DE',
  'french': 'FR',
  'spanish': 'ES',
  'italian': 'IT',
  'portuguese': 'PT',
  'brazilian portuguese': 'BR',
  'polish': 'PL',
  'ukrainian': 'UA',
  'czech': 'CS',
  'slovak': 'SK',
  'hungarian': 'HU',
  'romanian': 'RO',
  'bulgarian': 'BG',
  'greek': 'GR',
  'turkish': 'TR',
  'swedish': 'SE',
  'norwegian': 'NO',
  'danish': 'DK',
  'finnish': 'FI',
  'dutch': 'NL',
  'icelandic': 'IS',
  'croatian': 'HR',
  'serbian': 'RS',
  'slovenian': 'SI',
  'estonian': 'EE',
  'latvian': 'LV',
  'lithuanian': 'LT',
  'japanese': 'JP',
  'korean': 'KR',
  'chinese': 'CN',
  'arabic': 'AR',
  'hebrew': 'IL',
  'persian': 'IR',
  'hindi': 'IN',
  'thai': 'TH',
  'vietnamese': 'VN',
};

List<String> _layoutNames(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return [
    for (final entry in value)
      if (entry is String && entry.trim().isNotEmpty) entry.trim(),
  ];
}

/// Parses `swaymsg -t get_inputs`. Sway has no `main` flag; the first
/// keyboard that publishes layout data is used, falling back to the first
/// keyboard in compositor order. Other keyboards are ignored.
@visibleForTesting
KeyboardLayoutState? parseSwayInputs(Object? json) {
  if (json is! List) {
    return null;
  }
  Map<String, dynamic>? firstKeyboard;
  Map<String, dynamic>? withLayout;
  for (final input in json) {
    if (input is! Map<String, dynamic> || input['type'] != 'keyboard') {
      continue;
    }
    firstKeyboard ??= input;
    final names =
        input['xkb_layout_names'] ??
        (input['xkb_layout'] is String
            ? (input['xkb_layout']! as String).split(',')
            : null);
    if (names != null && names is List && names.isNotEmpty) {
      withLayout ??= input;
    }
  }
  final selected = withLayout ?? firstKeyboard;
  if (selected == null) {
    return const KeyboardLayoutState(backend: 'sway');
  }
  var names = _layoutNames(selected['xkb_layout_names']);
  if (names.isEmpty && selected['xkb_layout'] is String) {
    names = [
      for (final name in (selected['xkb_layout']! as String).split(','))
        if (name.trim().isNotEmpty) name.trim(),
    ];
  }
  final rawIndex = selected['xkb_active_layout_index'];
  final index = rawIndex is num ? rawIndex.toInt() : (names.isEmpty ? null : 0);
  final activeName = selected['xkb_active_layout_name'];
  var active = shortLayoutCode(activeName is String ? activeName : null);
  if (active == null && index != null && index >= 0 && index < names.length) {
    active = shortLayoutCode(names[index]);
  }
  if (names.isEmpty && activeName is String && activeName.trim().isNotEmpty) {
    names = [activeName.trim()];
  }
  return KeyboardLayoutState(
    available: true,
    backend: 'sway',
    active: active,
    index: index,
    names: names,
  );
}

/// Sway keyboard layouts over its i3-ipc socket.
///
/// The event connection is also the query connection: subscribe to `input`
/// events, request GET_INPUTS once, then re-query only when an input event
/// arrives. There is no polling and no idle pause.
class SwayKeyboardLayout implements KeyboardLayoutBackend {
  SwayKeyboardLayout({String? socketPath}) : _socketPath = socketPath;

  static const _maxReplyBytes = 1 << 20;
  static const _reconnectDelayBase = Duration(milliseconds: 500);
  static const _reconnectDelayMax = Duration(seconds: 5);
  static const _getInputs = 100;
  static const _inputEventType = 0x80000015;

  final String? _socketPath;
  Socket? _socket;
  Timer? _reconnect;
  Duration _reconnectDelay = _reconnectDelayBase;
  var _generation = 0;
  var _running = false;
  var _disposed = false;
  KeyboardLayoutState? _last;
  final _buffer = <int>[];
  final _controller = StreamController<KeyboardLayoutState>.broadcast();

  String? get _path => _socketPath ?? Platform.environment['SWAYSOCK'];

  @override
  Stream<KeyboardLayoutState> get snapshots => _controller.stream;

  @override
  Future<void> start() async {
    if (_running || _disposed) {
      return;
    }
    _running = true;
    final path = _path;
    if (path == null) {
      _emit(const KeyboardLayoutState(backend: 'sway'));
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
      if (_last == null) {
        _emit(const KeyboardLayoutState(backend: 'sway'));
      }
      _scheduleReconnect(generation);
      return;
    }
    if (generation != _generation || _disposed || !_running) {
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
    socket.add(_frame(2, utf8.encode('["input"]')));
    socket.add(_frame(_getInputs, Uint8List(0)));
  }

  void _scheduleReconnect(int generation) {
    if (_disposed || !_running || generation != _generation) {
      return;
    }
    _generation += 1;
    _socket = null;
    _reconnect?.cancel();
    _reconnect = Timer(_reconnectDelay, () {
      _reconnect = null;
      if (!_disposed && _running) {
        final path = _path;
        if (path != null) {
          unawaited(_dial(path, _generation));
        }
      }
    });
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectDelayMax ? _reconnectDelayMax : next;
  }

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
    if (type == _getInputs) {
      try {
        final state = parseSwayInputs(jsonDecode(utf8.decode(payload)));
        if (state != null) {
          _emit(state);
        }
      } on Object {
        return;
      }
      return;
    }
    if (type == _inputEventType) {
      _socket?.add(_frame(_getInputs, Uint8List(0)));
    }
  }

  void _emit(KeyboardLayoutState state) {
    if (_last == state || _controller.isClosed) {
      return;
    }
    _last = state;
    _controller.add(state);
  }

  static bool _hasMagic(List<int> bytes, int offset) {
    return bytes[offset] == 0x69 &&
        bytes[offset + 1] == 0x33 &&
        bytes[offset + 2] == 0x2d &&
        bytes[offset + 3] == 0x69 &&
        bytes[offset + 4] == 0x70 &&
        bytes[offset + 5] == 0x63;
  }

  static int _readUint32(List<int> bytes, int offset) {
    return ByteData.sublistView(
      Uint8List.fromList(bytes),
      offset,
      offset + 4,
    ).getUint32(0, Endian.little);
  }

  static Uint8List _frame(int type, List<int> payload) {
    final header = Uint8List(14);
    header.setAll(0, <int>[0x69, 0x33, 0x2d, 0x69, 0x70, 0x63]);
    final view = ByteData.sublistView(header);
    view.setUint32(6, payload.length, Endian.little);
    view.setUint32(10, type, Endian.little);
    return Uint8List.fromList([...header, ...payload]);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _running = false;
    _generation += 1;
    _reconnect?.cancel();
    _reconnect = null;
    await _socket?.close();
    _socket = null;
    _buffer.clear();
    await _controller.close();
  }
}

/// niri keyboard layouts over its JSON event stream.
///
/// The event stream supplies the full layout state on connect
/// (`KeyboardLayoutsChanged`) and switches (`KeyboardLayoutSwitched`); niri
/// has one configured set rather than per-keyboard layouts. No polling and no
/// idle pause.
class NiriKeyboardLayout implements KeyboardLayoutBackend {
  NiriKeyboardLayout({String? socketPath}) : _socketPath = socketPath;

  static const _maxReplyBytes = 1 << 20;
  static const _reconnectDelayBase = Duration(milliseconds: 500);
  static const _reconnectDelayMax = Duration(seconds: 5);

  final String? _socketPath;
  Socket? _socket;
  Timer? _reconnect;
  Duration _reconnectDelay = _reconnectDelayBase;
  var _generation = 0;
  var _running = false;
  var _disposed = false;
  List<String> _names = const [];
  KeyboardLayoutState? _last;
  final _controller = StreamController<KeyboardLayoutState>.broadcast();

  String? get _path => _socketPath ?? Platform.environment['NIRI_SOCKET'];

  @override
  Stream<KeyboardLayoutState> get snapshots => _controller.stream;

  @override
  Future<void> start() async {
    if (_running || _disposed) {
      return;
    }
    _running = true;
    final path = _path;
    if (path == null) {
      _emit(const KeyboardLayoutState(backend: 'niri'));
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
      if (_last == null) {
        _emit(const KeyboardLayoutState(backend: 'niri'));
      }
      _scheduleReconnect(generation);
      return;
    }
    if (generation != _generation || _disposed || !_running) {
      await socket.close();
      return;
    }
    _socket = socket;
    _reconnectDelay = _reconnectDelayBase;
    final pending = <int>[];
    socket.listen(
      (data) {
        pending.addAll(data);
        var newline = pending.indexOf(0x0A);
        while (newline != -1) {
          final line = utf8.decode(
            pending.sublist(0, newline),
            allowMalformed: true,
          );
          pending.removeRange(0, newline + 1);
          _handle(line);
          newline = pending.indexOf(0x0A);
        }
        if (pending.length > _maxReplyBytes) {
          pending.clear();
        }
      },
      onError: (_) {},
      onDone: () => _scheduleReconnect(generation),
    );
    socket.add(utf8.encode('${jsonEncode({'EventStream': null})}\n'));
  }

  void _scheduleReconnect(int generation) {
    if (_disposed || !_running || generation != _generation) {
      return;
    }
    _generation += 1;
    _socket = null;
    _reconnect?.cancel();
    _reconnect = Timer(_reconnectDelay, () {
      _reconnect = null;
      if (!_disposed && _running) {
        final path = _path;
        if (path != null) {
          unawaited(_dial(path, _generation));
        }
      }
    });
    final next = _reconnectDelay * 2;
    _reconnectDelay = next > _reconnectDelayMax ? _reconnectDelayMax : next;
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
      final changed = decoded['KeyboardLayoutsChanged'];
      if (changed is Map) {
        final layouts = changed['keyboard_layouts'];
        if (layouts is! Map) {
          return;
        }
        _names = _layoutNames(layouts['names']);
        final index = (layouts['current_idx'] as num?)?.toInt();
        _emitState(index);
        return;
      }
      final switched = decoded['KeyboardLayoutSwitched'];
      if (switched is Map) {
        final index = (switched['idx'] as num?)?.toInt();
        _emitState(index);
      }
    } on Object {
      return;
    }
  }

  void _emitState(int? index) {
    if (_names.isEmpty) {
      _emit(const KeyboardLayoutState(backend: 'niri'));
      return;
    }
    final resolved = index != null && index >= 0 && index < _names.length
        ? index
        : 0;
    _emit(
      KeyboardLayoutState(
        available: true,
        backend: 'niri',
        active: shortLayoutCode(_names[resolved]),
        index: resolved,
        names: _names,
      ),
    );
  }

  void _emit(KeyboardLayoutState state) {
    if (_last == state || _controller.isClosed) {
      return;
    }
    _last = state;
    _controller.add(state);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _running = false;
    _generation += 1;
    _reconnect?.cancel();
    _reconnect = null;
    await _socket?.close();
    _socket = null;
    await _controller.close();
  }
}
