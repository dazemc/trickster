import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

enum MprisPlaybackStatus { playing, paused, stopped }

@immutable
class MprisPlaybackState extends Equatable {
  const MprisPlaybackState({
    required this.serviceName,
    required this.identity,
    required this.title,
    required this.artists,
    required this.album,
    required this.artUrl,
    required this.length,
    required this.position,
    required this.observedAt,
    required this.status,
    required this.canGoNext,
    required this.canGoPrevious,
    required this.canPlay,
    required this.canPause,
  });

  MprisPlaybackState.unavailable()
    : serviceName = '',
      identity = '',
      title = '',
      artists = const <String>[],
      album = '',
      artUrl = '',
      length = Duration.zero,
      position = Duration.zero,
      observedAt = DateTime.fromMillisecondsSinceEpoch(0),
      status = MprisPlaybackStatus.stopped,
      canGoNext = false,
      canGoPrevious = false,
      canPlay = false,
      canPause = false;

  final String serviceName;
  final String identity;
  final String title;
  final List<String> artists;
  final String album;
  final String artUrl;
  final Duration length;
  final Duration position;
  final DateTime observedAt;
  final MprisPlaybackStatus status;
  final bool canGoNext;
  final bool canGoPrevious;
  final bool canPlay;
  final bool canPause;

  bool get available =>
      serviceName.isNotEmpty &&
      (status == MprisPlaybackStatus.playing ||
          status == MprisPlaybackStatus.paused);

  bool get playing => status == MprisPlaybackStatus.playing;

  String get artistLabel => artists.join(', ');

  Duration positionAt(DateTime now) {
    if (!playing || length <= Duration.zero) {
      return position;
    }
    final elapsed = now.difference(observedAt);
    if (elapsed.isNegative) {
      return position;
    }
    final advanced = position + elapsed;
    return advanced > length ? length : advanced;
  }

  Map<String, Object?> toJson() => {
    'serviceName': serviceName,
    'identity': identity,
    'title': title,
    'artists': artists,
    'album': album,
    'artUrl': artUrl,
    'length': length.inMicroseconds,
    'position': position.inMicroseconds,
    'observedAt': observedAt.millisecondsSinceEpoch,
    'status': status.name,
    'canGoNext': canGoNext,
    'canGoPrevious': canGoPrevious,
    'canPlay': canPlay,
    'canPause': canPause,
  };

  static MprisPlaybackState fromJson(Map<String, dynamic> json) {
    return MprisPlaybackState(
      serviceName: json['serviceName'] as String? ?? '',
      identity: json['identity'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artists:
          (json['artists'] as List<dynamic>?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
      album: json['album'] as String? ?? '',
      artUrl: json['artUrl'] as String? ?? '',
      length: Duration(microseconds: (json['length'] as num?)?.toInt() ?? 0),
      position: Duration(
        microseconds: (json['position'] as num?)?.toInt() ?? 0,
      ),
      observedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['observedAt'] as num?)?.toInt() ?? 0,
      ),
      status: MprisPlaybackStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => MprisPlaybackStatus.stopped,
      ),
      canGoNext: json['canGoNext'] as bool? ?? false,
      canGoPrevious: json['canGoPrevious'] as bool? ?? false,
      canPlay: json['canPlay'] as bool? ?? false,
      canPause: json['canPause'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
    serviceName,
    identity,
    title,
    artists,
    album,
    artUrl,
    length,
    position,
    observedAt,
    status,
    canGoNext,
    canGoPrevious,
    canPlay,
    canPause,
  ];
}

class MediaPlayerService {
  MediaPlayerService({
    DBusClient? client,
    this.readTimeout = const Duration(seconds: 2),
    this.methodTimeout = const Duration(seconds: 4),
    this.recoveryInterval = const Duration(minutes: 1),
    this.signalCoalesce = const Duration(milliseconds: 45),
    this.unavailableGrace = const Duration(seconds: 2),
  }) : _client = client;

  static const String servicePrefix = 'org.mpris.MediaPlayer2.';
  static const String objectPath = '/org/mpris/MediaPlayer2';
  static const String rootInterface = 'org.mpris.MediaPlayer2';
  static const String playerInterface = 'org.mpris.MediaPlayer2.Player';
  static const int _maxPlayers = 16;

  final Duration readTimeout;
  final Duration methodTimeout;
  final Duration recoveryInterval;
  final Duration signalCoalesce;
  final Duration unavailableGrace;

  DBusClient? _client;
  final StreamController<MprisPlaybackState> _snapshots =
      StreamController<MprisPlaybackState>.broadcast(sync: true);

  StreamSubscription<DBusNameOwnerChangedEvent>? _ownerSubscription;
  StreamSubscription<DBusPropertiesChangedSignal>? _propertiesSubscription;
  Timer? _refreshTimer;
  Timer? _signalTimer;
  Timer? _unavailableTimer;
  DBusRemoteObject? _activeObject;
  MprisPlaybackState _current = MprisPlaybackState.unavailable();
  bool _started = false;
  bool _disposed = false;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _unavailableGraceElapsed = false;

  DBusClient get _bus => _client ??= DBusClient.session();

  Stream<MprisPlaybackState> get snapshots => _snapshots.stream;

  MprisPlaybackState get current => _current;

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _ownerSubscription = _bus.nameOwnerChanged
        .where((event) => event.name.startsWith(servicePrefix))
        .listen((_) => _scheduleRefresh(immediate: true));
    _refreshTimer = Timer.periodic(
      recoveryInterval,
      (_) => _scheduleRefresh(immediate: true),
    );
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshAgain = false;
        final names = await _listPlayerNames();
        final candidates = await Future.wait(
          names.take(_maxPlayers).map(_readPlayer),
        );
        final live = candidates.whereType<_MprisCandidate>().toList()
          ..sort((left, right) {
            final byStatus = _statusPriority(
              left.state.status,
            ).compareTo(_statusPriority(right.state.status));
            return byStatus != 0
                ? byStatus
                : left.state.identity.compareTo(right.state.identity);
          });
        final candidate = live.isEmpty ? null : live.first;
        if (candidate == null || !candidate.state.available) {
          await _handleUnavailable();
        } else {
          _cancelUnavailableGrace();
          await _selectPlayer(candidate.object);
          _emit(candidate.state);
        }
      } while (_refreshAgain && !_disposed);
    } on Object {
      if (!_disposed) {
        await _handleUnavailable();
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> previous() => _invoke('Previous', _current.canGoPrevious);

  Future<void> next() => _invoke('Next', _current.canGoNext);

  Future<void> playPause() => _invoke(
    'PlayPause',
    _current.playing ? _current.canPause : _current.canPlay,
  );

  Future<void> _invoke(String method, bool supported) async {
    final object = _activeObject;
    if (object == null || !supported || _disposed) {
      return;
    }
    try {
      await object
          .callMethod(
            playerInterface,
            method,
            const <DBusValue>[],
            replySignature: DBusSignature(''),
          )
          .timeout(methodTimeout);
    } on Object {
      // The player can disappear between hover and click.
    }
  }

  Future<List<String>> _listPlayerNames() async {
    return (await _bus.listNames().timeout(
      readTimeout,
    )).where((name) => name.startsWith(servicePrefix)).toList(growable: false);
  }

  Future<_MprisCandidate?> _readPlayer(String serviceName) async {
    final object = DBusRemoteObject(
      _bus,
      name: serviceName,
      path: DBusObjectPath(objectPath),
    );
    try {
      final values = await Future.wait([
        object.getAllProperties(playerInterface).timeout(readTimeout),
        object.getAllProperties(rootInterface).timeout(readTimeout),
      ]);
      final player = values[0];
      final root = values[1];
      final status = _playbackStatus(_string(player['PlaybackStatus']));
      if (status == MprisPlaybackStatus.stopped) {
        return null;
      }
      final metadata = _variantDict(player['Metadata']);
      final now = DateTime.now();
      final lengthMicros = _integer(
        metadata['mpris:length'],
      ).clamp(0, const Duration(days: 7).inMicroseconds).toInt();
      final positionMicros = _integer(player['Position'])
          .clamp(
            0,
            lengthMicros > 0
                ? lengthMicros
                : const Duration(days: 7).inMicroseconds,
          )
          .toInt();
      final title = _boundedText(_string(metadata['xesam:title']), 256);
      final identity = _boundedText(
        _string(root['Identity'], fallback: _serviceIdentity(serviceName)),
        128,
      );
      return _MprisCandidate(
        object: object,
        state: MprisPlaybackState(
          serviceName: serviceName,
          identity: identity,
          title: title.isEmpty ? identity : title,
          artists: List<String>.unmodifiable(
            _strings(metadata['xesam:artist'])
                .map((artist) => _boundedText(artist, 128))
                .where((artist) => artist.isNotEmpty)
                .take(8),
          ),
          album: _boundedText(_string(metadata['xesam:album']), 256),
          artUrl: _safeArtworkUrl(_string(metadata['mpris:artUrl'])),
          length: Duration(microseconds: lengthMicros),
          position: Duration(microseconds: positionMicros),
          observedAt: now,
          status: status,
          canGoNext: _boolean(player['CanGoNext']),
          canGoPrevious: _boolean(player['CanGoPrevious']),
          canPlay: _boolean(player['CanPlay']),
          canPause: _boolean(player['CanPause']),
        ),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _selectPlayer(DBusRemoteObject? object) async {
    if (_activeObject?.name == object?.name) {
      return;
    }
    await _propertiesSubscription?.cancel();
    _propertiesSubscription = null;
    _activeObject = object;
    if (object != null) {
      _propertiesSubscription = object.propertiesChanged
          .where((signal) => signal.propertiesInterface == playerInterface)
          .listen(_handlePropertiesChanged);
    }
  }

  void _handlePropertiesChanged(DBusPropertiesChangedSignal signal) {
    if (_disposed || _activeObject?.name != _current.serviceName) {
      return;
    }
    if (signal.invalidatedProperties.isNotEmpty) {
      _scheduleRefresh();
      return;
    }
    final next = applyMprisPlayerProperties(
      _current,
      signal.changedProperties,
      DateTime.now(),
    );
    if (next == null) {
      return;
    }
    if (!next.available) {
      // Another paused or playing service may already be available. A full
      // scan happens only on this topology-relevant transition, not for every
      // metadata or position signal.
      _scheduleRefresh();
      return;
    }
    _cancelUnavailableGrace();
    _emit(next);
  }

  void _scheduleRefresh({bool immediate = false}) {
    if (_disposed) {
      return;
    }
    _signalTimer?.cancel();
    _signalTimer = Timer(
      immediate ? Duration.zero : signalCoalesce,
      () => unawaited(refresh()),
    );
  }

  Future<void> _handleUnavailable() async {
    if (_current.available && !_unavailableGraceElapsed) {
      _unavailableTimer ??= Timer(unavailableGrace, () {
        _unavailableTimer = null;
        _unavailableGraceElapsed = true;
        _scheduleRefresh(immediate: true);
      });
      return;
    }
    _cancelUnavailableGrace();
    await _selectPlayer(null);
    _emit(MprisPlaybackState.unavailable());
  }

  void _cancelUnavailableGrace() {
    _unavailableTimer?.cancel();
    _unavailableTimer = null;
    _unavailableGraceElapsed = false;
  }

  void _emit(MprisPlaybackState state) {
    _current = state;
    if (!_snapshots.isClosed) {
      _snapshots.add(state);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _refreshTimer?.cancel();
    _signalTimer?.cancel();
    _unavailableTimer?.cancel();
    await _ownerSubscription?.cancel();
    await _propertiesSubscription?.cancel();
    await _snapshots.close();
    await _client?.close();
  }
}

class _MprisCandidate {
  const _MprisCandidate({required this.object, required this.state});

  final DBusRemoteObject object;
  final MprisPlaybackState state;
}

@visibleForTesting
MprisPlaybackState? applyMprisPlayerProperties(
  MprisPlaybackState current,
  Map<String, DBusValue> changed,
  DateTime now,
) {
  const relevant = <String>{
    'PlaybackStatus',
    'Metadata',
    'Position',
    'CanGoNext',
    'CanGoPrevious',
    'CanPlay',
    'CanPause',
  };
  if (!changed.keys.any(relevant.contains)) {
    return null;
  }

  final metadataChanged = changed.containsKey('Metadata');
  final metadata = metadataChanged
      ? _variantDict(changed['Metadata'])
      : const <String, DBusValue>{};
  final lengthMicros = metadataChanged
      ? _integer(
          metadata['mpris:length'],
        ).clamp(0, const Duration(days: 7).inMicroseconds).toInt()
      : current.length.inMicroseconds;
  final positionMicros = changed.containsKey('Position')
      ? _integer(changed['Position'])
            .clamp(
              0,
              lengthMicros > 0
                  ? lengthMicros
                  : const Duration(days: 7).inMicroseconds,
            )
            .toInt()
      : current
            .positionAt(now)
            .inMicroseconds
            .clamp(0, lengthMicros > 0 ? lengthMicros : 1 << 53)
            .toInt();
  final title = metadataChanged
      ? _boundedText(_string(metadata['xesam:title']), 256)
      : current.title;
  final artists = metadataChanged
      ? List<String>.unmodifiable(
          _strings(metadata['xesam:artist'])
              .map((artist) => _boundedText(artist, 128))
              .where((artist) => artist.isNotEmpty)
              .take(8),
        )
      : current.artists;

  return MprisPlaybackState(
    serviceName: current.serviceName,
    identity: current.identity,
    title: metadataChanged
        ? (title.isEmpty ? current.identity : title)
        : current.title,
    artists: artists,
    album: metadataChanged
        ? _boundedText(_string(metadata['xesam:album']), 256)
        : current.album,
    artUrl: metadataChanged
        ? _safeArtworkUrl(_string(metadata['mpris:artUrl']))
        : current.artUrl,
    length: Duration(microseconds: lengthMicros),
    position: Duration(microseconds: positionMicros),
    observedAt: now,
    status: changed.containsKey('PlaybackStatus')
        ? _playbackStatus(_string(changed['PlaybackStatus']))
        : current.status,
    canGoNext: changed.containsKey('CanGoNext')
        ? _boolean(changed['CanGoNext'])
        : current.canGoNext,
    canGoPrevious: changed.containsKey('CanGoPrevious')
        ? _boolean(changed['CanGoPrevious'])
        : current.canGoPrevious,
    canPlay: changed.containsKey('CanPlay')
        ? _boolean(changed['CanPlay'])
        : current.canPlay,
    canPause: changed.containsKey('CanPause')
        ? _boolean(changed['CanPause'])
        : current.canPause,
  );
}

int _statusPriority(MprisPlaybackStatus status) {
  switch (status) {
    case MprisPlaybackStatus.playing:
      return 0;
    case MprisPlaybackStatus.paused:
      return 1;
    case MprisPlaybackStatus.stopped:
      return 2;
  }
}

MprisPlaybackStatus _playbackStatus(String value) {
  switch (value) {
    case 'Playing':
      return MprisPlaybackStatus.playing;
    case 'Paused':
      return MprisPlaybackStatus.paused;
    default:
      return MprisPlaybackStatus.stopped;
  }
}

Map<String, DBusValue> _variantDict(DBusValue? value) {
  try {
    return value?.asStringVariantDict() ?? const <String, DBusValue>{};
  } on Object {
    return const <String, DBusValue>{};
  }
}

String _string(DBusValue? value, {String fallback = ''}) {
  return value is DBusString ? value.value : fallback;
}

bool _boolean(DBusValue? value) {
  return value is DBusBoolean && value.value;
}

int _integer(DBusValue? value) {
  if (value is DBusInt64) {
    return value.value;
  }
  if (value is DBusUint64) {
    return value.value;
  }
  return 0;
}

Iterable<String> _strings(DBusValue? value) {
  try {
    return value?.asStringArray() ?? const <String>[];
  } on Object {
    return const <String>[];
  }
}

String _serviceIdentity(String serviceName) {
  return serviceName
      .substring(MediaPlayerService.servicePrefix.length)
      .split('.')
      .first;
}

String _safeArtworkUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      (uri.scheme != 'file' && uri.scheme != 'http' && uri.scheme != 'https')) {
    return '';
  }
  return uri.toString();
}

String _boundedText(String value, int maximumRunes) {
  final normalized = value
      .replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return String.fromCharCodes(
    normalized.runes.take(maximumRunes).toList(growable: false),
  );
}
