import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:math' as math;

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
    DBusClient Function()? clientFactory,
    this.readTimeout = const Duration(seconds: 2),
    this.methodTimeout = const Duration(seconds: 4),
    this.recoveryInterval = const Duration(minutes: 1),
    this.signalCoalesce = const Duration(milliseconds: 45),
    this.unavailableGrace = const Duration(seconds: 2),
    List<Duration> recoveryBackoff = const <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
    ],
  }) : assert(
         client == null || clientFactory != null,
         'a fixed client needs a clientFactory for transport recovery',
       ),
       _client = client,
       _clientFactory = clientFactory ?? DBusClient.session,
       _recoveryBackoff = recoveryBackoff;

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

  final DBusClient Function() _clientFactory;
  final List<Duration> _recoveryBackoff;
  DBusClient? _client;
  final StreamController<MprisPlaybackState> _snapshots =
      StreamController<MprisPlaybackState>.broadcast(sync: true);

  // Cancelled indirectly by _cancelSubscriptions on recovery and dispose.
  // ignore: cancel_subscriptions
  StreamSubscription<DBusNameOwnerChangedEvent>? _ownerSubscription;
  StreamSubscription<DBusPropertiesChangedSignal>? _propertiesSubscription;
  Timer? _refreshTimer;
  Timer? _signalTimer;
  Timer? _unavailableTimer;
  Timer? _recoveryTimer;
  Future<void>? _recovery;
  Completer<void>? _refreshIdle;
  DBusRemoteObject? _activeObject;
  MprisPlaybackState _current = MprisPlaybackState.unavailable();
  int _recoveryAttempt = 0;
  int _connectionGeneration = 0;
  bool _started = false;
  bool _disposed = false;
  bool _refreshing = false;
  bool _refreshAgain = false;
  bool _refreshTransportFailure = false;
  bool _recoveryPending = false;
  bool _unavailableGraceElapsed = false;

  DBusClient get _bus {
    final client = _client;
    if (client == null) {
      throw StateError('MediaPlayerService is not connected');
    }
    return client;
  }

  Stream<MprisPlaybackState> get snapshots => _snapshots.stream;

  MprisPlaybackState get current => _current;

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    try {
      _client ??= _clientFactory();
      _refreshTimer = Timer.periodic(
        recoveryInterval,
        (_) => _scheduleRefresh(immediate: true),
      );
      await refresh();
      if (!_disposed && !_refreshTransportFailure) {
        _subscribeOwnerChanges();
      }
    } on Object {
      // The service stays alive and the recovery timer retries.
      _scheduleRecovery();
    }
  }

  void _subscribeOwnerChanges() {
    _ownerSubscription = _bus.nameOwnerChanged
        .where((event) => event.name.startsWith(servicePrefix))
        .listen(
          (_) => _scheduleRefresh(immediate: true),
          onError: _onTransportFailure,
        );
  }

  void _onTransportFailure(Object error) {
    if (_disposed) {
      return;
    }
    if (_refreshing) {
      _refreshTransportFailure = true;
    }
    if (_recovery != null) {
      _recoveryPending = true;
    }
    _scheduleRecovery();
  }

  bool _isTransportFailure(Object error) {
    return error is DBusClosedException ||
        error is SocketException ||
        error is TimeoutException;
  }

  void _scheduleRecovery({bool afterFailure = false}) {
    if (_disposed ||
        _recoveryTimer != null ||
        (!afterFailure && _recovery != null)) {
      return;
    }
    final index = math.min(_recoveryAttempt, _recoveryBackoff.length - 1);
    final delay = _recoveryBackoff[index];
    _recoveryAttempt += 1;
    _recoveryTimer = Timer(delay, () {
      _recoveryTimer = null;
      if (_disposed) {
        return;
      }
      final recovery = _recover();
      _recovery = recovery;
      unawaited(
        recovery
            .then<void>(
              (_) {},
              onError: (Object error, StackTrace stackTrace) {
                _scheduleRecovery(afterFailure: true);
              },
            )
            .whenComplete(() {
              if (identical(_recovery, recovery)) {
                _recovery = null;
              }
            }),
      );
    });
  }

  Future<void> _recover() async {
    if (_disposed) {
      return;
    }
    _connectionGeneration += 1;
    await _cancelSubscriptions();
    _signalTimer?.cancel();
    _signalTimer = null;
    _cancelUnavailableGrace();
    await _selectPlayer(null);
    _emit(MprisPlaybackState.unavailable());

    final idle = _refreshIdle;
    if (idle != null) {
      try {
        await idle.future.timeout(readTimeout + methodTimeout);
      } on Object {
        // A refresh stuck on the old transport must not block the rebuild.
      }
    }
    final oldClient = _client;
    _client = null;
    if (oldClient != null) {
      try {
        await oldClient.close().timeout(readTimeout);
      } on Object {
        // The old socket is already gone; the client is discarded.
      }
    }
    if (_disposed) {
      return;
    }
    try {
      _client = _clientFactory();
      // Confirm the new transport before subscribing or resetting backoff;
      // discovery will select and re-subscribe the player on this connection.
      await _bus.listNames().timeout(readTimeout);
      if (_disposed) {
        return;
      }
      _subscribeOwnerChanges();
      _refreshTransportFailure = false;
      _recoveryPending = false;
      await refresh();
      if (_disposed) {
        return;
      }
      if (_refreshTransportFailure || _recoveryPending) {
        _scheduleRecovery(afterFailure: true);
        return;
      }
      _recoveryAttempt = 0;
    } on Object {
      if (!_disposed) {
        _scheduleRecovery(afterFailure: true);
      }
    }
  }

  Future<void> _cancelSubscriptions() async {
    final owner = _ownerSubscription;
    _ownerSubscription = null;
    try {
      await owner?.cancel();
    } on Object {
      // A dead transport can make match-rule removal fail; discard it.
    }
    final properties = _propertiesSubscription;
    _propertiesSubscription = null;
    try {
      await properties?.cancel();
    } on Object {
      // Same as above.
    }
  }

  Future<void> refresh() async {
    if (_disposed || _client == null) {
      return;
    }
    if (_refreshing) {
      _refreshAgain = true;
      final idle = _refreshIdle;
      if (idle != null) {
        await idle.future;
      }
      return;
    }
    _refreshing = true;
    final completion = Completer<void>();
    _refreshIdle = completion;
    final generation = _connectionGeneration;
    _refreshTransportFailure = false;
    try {
      do {
        _refreshAgain = false;
        if (_disposed || generation != _connectionGeneration) {
          return;
        }
        final names = await _listPlayerNames();
        if (_disposed || generation != _connectionGeneration) {
          return;
        }
        final candidates = await Future.wait(
          names.take(_maxPlayers).map(_readPlayer),
        );
        if (_disposed || generation != _connectionGeneration) {
          return;
        }
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
          final resynced = await _selectPlayer(candidate.object);
          if (_disposed || generation != _connectionGeneration) {
            return;
          }
          _emit(resynced ?? candidate.state);
        }
      } while (_refreshAgain && !_disposed);
    } on Object catch (error) {
      if (!_disposed && generation == _connectionGeneration) {
        if (_isTransportFailure(error)) {
          _refreshTransportFailure = true;
          _onTransportFailure(error);
        }
        await _handleUnavailable();
      }
    } finally {
      _refreshing = false;
      if (!completion.isCompleted) {
        completion.complete();
      }
      if (identical(_refreshIdle, completion)) {
        _refreshIdle = null;
      }
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
    } on Object catch (error) {
      if (_isTransportFailure(error)) {
        _onTransportFailure(error);
      }
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
    } on Object catch (error) {
      if (_isTransportFailure(error)) {
        _onTransportFailure(error);
      }
      return null;
    }
  }

  /// Swaps the active player, installing its PropertiesChanged match. The
  /// match registers asynchronously, so a change landing between discovery's
  /// read and the live match would otherwise wait for the recovery scan: the
  /// new subscription re-reads once and returns that state to the caller.
  Future<MprisPlaybackState?> _selectPlayer(DBusRemoteObject? object) async {
    if (_activeObject?.name == object?.name) {
      return null;
    }
    await _propertiesSubscription?.cancel();
    _propertiesSubscription = null;
    _activeObject = object;
    if (object == null) {
      return null;
    }
    _propertiesSubscription = object.propertiesChanged
        .where((signal) => signal.propertiesInterface == playerInterface)
        .listen(_handlePropertiesChanged, onError: _onTransportFailure);
    final fresh = await _readPlayer(object.name);
    if (_disposed || _activeObject?.name != object.name) {
      return null;
    }
    return fresh?.state;
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
    _refreshTimer = null;
    _signalTimer?.cancel();
    _signalTimer = null;
    _unavailableTimer?.cancel();
    _unavailableTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    final recovery = _recovery;
    if (recovery != null) {
      try {
        await recovery.timeout(const Duration(seconds: 3));
      } on Object {
        // A recovery that cannot finish must not keep timers or clients alive.
      }
    }
    await _cancelSubscriptions();
    await _snapshots.close();
    final client = _client;
    _client = null;
    try {
      await client?.close();
    } on Object {
      // Best effort during shutdown.
    }
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
