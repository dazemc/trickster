import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/mpris.dart';

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Re-emits [changed] until [condition] holds. The dbus package installs the
/// PropertiesChanged match rule without awaiting the bus round-trip, so the
/// first signal after discovery can precede the rule; production absorbs that
/// with the recovery timer.
Future<void> _emitUntil(
  _FakePlayerObject player,
  Map<String, DBusValue> changed,
  bool Function() condition,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    await player.emitChanged(changed);
    if (condition()) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out emitting change');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

/// An in-process message bus: the real D-Bus codec, a fake session bus.
class _FakeBus {
  _FakeBus._(this.server, this.address, this.directory);

  DBusServer server;
  final DBusAddress address;
  final Directory directory;

  static Future<_FakeBus> start() async {
    final directory = await Directory.systemTemp.createTemp('trickster-mpris');
    final server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress('unix:path=${directory.path}/bus'),
    );
    return _FakeBus._(server, address, directory);
  }

  DBusClient client() => DBusClient(address);

  /// Drops every connected client and starts a fresh server on the same path.
  Future<void> restart() async {
    await server.close();
    final socket = File(address.properties['path']!);
    if (socket.existsSync()) {
      socket.deleteSync();
    }
    final next = DBusServer();
    await next.listenAddress(address);
    server = next;
  }

  Future<void> dispose() async {
    await server.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}

/// A minimal `org.mpris.MediaPlayer2` exporter served by the fake bus.
class _FakePlayerObject extends DBusObject {
  _FakePlayerObject() : super(DBusObjectPath(MediaPlayerService.objectPath));

  String identity = 'Fake Player';
  String playbackStatus = 'Playing';
  String title = 'Test Song';
  List<String> artists = <String>['Test Artist'];
  String album = 'Test Album';
  String artUrl = 'file:///tmp/cover.png';
  int lengthMicros = 180000000;
  int positionMicros = 42000000;
  bool canGoNext = true;
  bool canGoPrevious = true;
  bool canPlay = true;
  bool canPause = true;

  final calls = <String>[];
  int playerGetAllCalls = 0;

  /// When set, the next player-interface GetAll captures its snapshot and
  /// then waits, letting a test mutate state in the discovery gap.
  Completer<void>? holdPlayerGetAll;
  bool playerGetAllHeld = false;

  Map<String, DBusValue> _playerProperties() => <String, DBusValue>{
    'PlaybackStatus': DBusString(playbackStatus),
    'Metadata': _metadata(),
    'Position': DBusInt64(positionMicros),
    'CanGoNext': DBusBoolean(canGoNext),
    'CanGoPrevious': DBusBoolean(canGoPrevious),
    'CanPlay': DBusBoolean(canPlay),
    'CanPause': DBusBoolean(canPause),
  };

  DBusValue _metadata() =>
      DBusDict(DBusSignature('s'), DBusSignature('v'), <DBusValue, DBusValue>{
        DBusString('xesam:title'): DBusVariant(DBusString(title)),
        DBusString('xesam:artist'): DBusVariant(DBusArray.string(artists)),
        DBusString('xesam:album'): DBusVariant(DBusString(album)),
        DBusString('mpris:artUrl'): DBusVariant(DBusString(artUrl)),
        DBusString('mpris:length'): DBusVariant(DBusInt64(lengthMicros)),
      });

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final properties = switch (interface) {
      MediaPlayerService.playerInterface => _playerProperties(),
      MediaPlayerService.rootInterface => <String, DBusValue>{
        'Identity': DBusString(identity),
      },
      _ => null,
    };
    if (properties == null) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final value = properties[name];
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface != MediaPlayerService.playerInterface) {
      return switch (interface) {
        MediaPlayerService.rootInterface => DBusGetAllPropertiesResponse(
          <String, DBusValue>{'Identity': DBusString(identity)},
        ),
        _ => DBusMethodErrorResponse.unknownInterface(),
      };
    }
    final snapshot = _playerProperties();
    playerGetAllCalls += 1;
    final gate = holdPlayerGetAll;
    if (gate != null && !gate.isCompleted) {
      playerGetAllHeld = true;
      await gate.future;
      playerGetAllHeld = false;
    }
    return DBusGetAllPropertiesResponse(snapshot);
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != MediaPlayerService.playerInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    if (methodCall.name == 'PlayPause' ||
        methodCall.name == 'Next' ||
        methodCall.name == 'Previous') {
      calls.add(methodCall.name);
      return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  Future<void> emitChanged(Map<String, DBusValue> changed) {
    return emitSignal(
      'org.freedesktop.DBus.Properties',
      'PropertiesChanged',
      <DBusValue>[
        DBusString(MediaPlayerService.playerInterface),
        DBusDict(DBusSignature('s'), DBusSignature('v'), <DBusValue, DBusValue>{
          for (final entry in changed.entries)
            DBusString(entry.key): DBusVariant(entry.value),
        }),
        DBusArray(DBusSignature('s')),
      ],
    );
  }
}

MediaPlayerService _service(
  _FakeBus bus, {
  List<MprisPlaybackState>? log,
  Duration recoveryInterval = const Duration(hours: 1),
  List<Duration> recoveryBackoff = const <Duration>[
    Duration(milliseconds: 20),
    Duration(milliseconds: 40),
    Duration(milliseconds: 80),
  ],
}) {
  final service = MediaPlayerService(
    client: bus.client(),
    clientFactory: bus.client,
    readTimeout: const Duration(seconds: 2),
    signalCoalesce: const Duration(milliseconds: 10),
    unavailableGrace: const Duration(milliseconds: 80),
    recoveryInterval: recoveryInterval,
    recoveryBackoff: recoveryBackoff,
  );
  if (log != null) {
    service.snapshots.listen(log.add);
  }
  return service;
}

/// Serves [player] on a fresh client with a well-known MPRIS name.
Future<DBusClient> _servePlayer(
  _FakeBus bus,
  _FakePlayerObject player,
  String name,
) async {
  final client = bus.client();
  await client.registerObject(player);
  await client.requestName('${MediaPlayerService.servicePrefix}$name');
  return client;
}

void main() {
  test('maps a fake player into playback state', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = _service(bus);
    addTearDown(service.dispose);
    await service.start();
    expect(service.current.available, isFalse);

    final player = _FakePlayerObject();
    final client = await _servePlayer(bus, player, 'fake');
    addTearDown(client.close);
    await _waitFor(() => service.current.available);

    final state = service.current;
    expect(state.serviceName, '${MediaPlayerService.servicePrefix}fake');
    expect(state.identity, 'Fake Player');
    expect(state.title, 'Test Song');
    expect(state.artists, <String>['Test Artist']);
    expect(state.artistLabel, 'Test Artist');
    expect(state.album, 'Test Album');
    expect(state.artUrl, 'file:///tmp/cover.png');
    expect(state.length, const Duration(microseconds: 180000000));
    expect(state.position, const Duration(microseconds: 42000000));
    expect(state.status, MprisPlaybackStatus.playing);
    expect(state.playing, isTrue);
    expect(state.canGoNext, isTrue);
    expect(state.canGoPrevious, isTrue);
    expect(state.canPlay, isTrue);
    expect(state.canPause, isTrue);

    player.playbackStatus = 'Paused';
    await _emitUntil(player, <String, DBusValue>{
      'PlaybackStatus': DBusString('Paused'),
    }, () => service.current.status == MprisPlaybackStatus.paused);
    expect(service.current.available, isTrue);
    expect(service.current.playing, isFalse);

    player.title = 'Renamed';
    player.artists = <String>['One', 'Two'];
    await _emitUntil(player, <String, DBusValue>{
      'Metadata': player._metadata(),
    }, () => service.current.title == 'Renamed');
    expect(service.current.artists, <String>['One', 'Two']);
  });

  test('converges when a change lands before the match installs', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = _service(bus);
    addTearDown(service.dispose);
    await service.start();

    final player = _FakePlayerObject();
    final gate = Completer<void>();
    player.holdPlayerGetAll = gate;
    final client = await _servePlayer(bus, player, 'race');
    addTearDown(client.close);

    // Discovery is blocked inside its read, so no PropertiesChanged match
    // exists yet. Mutate the player and announce the change: the signal is
    // lost, and only the resync after subscription can carry it.
    await _waitFor(() => player.playerGetAllHeld);
    player.playbackStatus = 'Paused';
    player.title = 'After Gap';
    await player.emitChanged(<String, DBusValue>{
      'PlaybackStatus': DBusString('Paused'),
      'Metadata': player._metadata(),
    });
    gate.complete();
    player.holdPlayerGetAll = null;

    await _waitFor(() => service.current.title == 'After Gap');
    expect(service.current.available, isTrue);
    expect(service.current.status, MprisPlaybackStatus.paused);
  });

  test('hides when no player claims the bus', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final snapshots = <MprisPlaybackState>[];
    final service = _service(bus, log: snapshots);
    addTearDown(service.dispose);
    await service.start();

    final player = _FakePlayerObject();
    final client = await _servePlayer(bus, player, 'fake');
    await _waitFor(() => service.current.available);
    await client.close();

    await _waitFor(() => !service.current.available);
    expect(service.current.serviceName, isEmpty);
    expect(snapshots.last.available, isFalse);
  });

  test('treats a stopped player as no player', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = _service(bus);
    addTearDown(service.dispose);
    await service.start();

    final player = _FakePlayerObject()..playbackStatus = 'Stopped';
    final client = await _servePlayer(bus, player, 'fake');
    addTearDown(client.close);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(service.current.available, isFalse);
  });

  test('prefers a playing player over a paused one', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = _service(bus);
    addTearDown(service.dispose);
    await service.start();

    final paused = _FakePlayerObject()
      ..identity = 'Aaa Paused'
      ..playbackStatus = 'Paused';
    final playing = _FakePlayerObject()
      ..identity = 'Zzz Playing'
      ..playbackStatus = 'Playing';
    final pausedClient = await _servePlayer(bus, paused, 'paused');
    final playingClient = await _servePlayer(bus, playing, 'playing');
    addTearDown(pausedClient.close);
    addTearDown(playingClient.close);
    await _waitFor(
      () =>
          service.current.serviceName ==
          '${MediaPlayerService.servicePrefix}playing',
    );
  });

  test('controls call the active player', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = _service(bus);
    addTearDown(service.dispose);
    await service.start();

    final player = _FakePlayerObject();
    final client = await _servePlayer(bus, player, 'fake');
    addTearDown(client.close);
    await _waitFor(() => service.current.available);

    await service.playPause();
    await service.next();
    await service.previous();
    expect(player.calls, <String>['PlayPause', 'Next', 'Previous']);

    player.canGoNext = false;
    await _emitUntil(player, <String, DBusValue>{
      'CanGoNext': const DBusBoolean(false),
    }, () => !service.current.canGoNext);
    await service.next();
    expect(player.calls, <String>['PlayPause', 'Next', 'Previous']);
  });

  test('applies property changes without a full refresh', () {
    final baseline = MprisPlaybackState(
      serviceName: 'org.mpris.MediaPlayer2.fake',
      identity: 'Fake Player',
      title: 'Test Song',
      artists: const <String>['Test Artist'],
      album: 'Test Album',
      artUrl: 'file:///tmp/cover.png',
      length: const Duration(seconds: 180),
      position: const Duration(seconds: 42),
      observedAt: DateTime.fromMillisecondsSinceEpoch(0),
      status: MprisPlaybackStatus.playing,
      canGoNext: true,
      canGoPrevious: true,
      canPlay: true,
      canPause: true,
    );
    final now = DateTime.fromMillisecondsSinceEpoch(5000);

    expect(
      applyMprisPlayerProperties(baseline, <String, DBusValue>{
        'Volume': const DBusDouble(0.5),
      }, now),
      isNull,
    );

    final paused = applyMprisPlayerProperties(baseline, <String, DBusValue>{
      'PlaybackStatus': const DBusString('Paused'),
    }, now)!;
    expect(paused.status, MprisPlaybackStatus.paused);
    expect(paused.title, 'Test Song');
    expect(paused.canGoNext, isTrue);
    // Position is extrapolated from the last observation while no absolute
    // Position arrives.
    expect(paused.position, const Duration(seconds: 47));

    final advanced = applyMprisPlayerProperties(baseline, <String, DBusValue>{
      'Position': const DBusInt64(5000000),
    }, now)!;
    expect(advanced.position, const Duration(seconds: 5));
    expect(advanced.observedAt, now);

    final renamed = applyMprisPlayerProperties(baseline, <String, DBusValue>{
      'Metadata': DBusDict(
        DBusSignature('s'),
        DBusSignature('v'),
        <DBusValue, DBusValue>{
          DBusString('xesam:title'): DBusVariant(const DBusString('New')),
        },
      ),
    }, now)!;
    expect(renamed.title, 'New');
    expect(renamed.length, Duration.zero);
  });

  test('rebuilds the client and player after the bus restarts', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = _service(
      bus,
      recoveryBackoff: const <Duration>[Duration(milliseconds: 200)],
    );
    addTearDown(service.dispose);
    await service.start();

    final before = _FakePlayerObject();
    final beforeClient = await _servePlayer(bus, before, 'fake');
    await _waitFor(() => service.current.available);

    await beforeClient.close();
    await bus.restart();
    // Trigger detection on the dead client; the 60s refresh timer remains
    // intentionally irrelevant to this test.
    await service.refresh();
    await _waitFor(() => !service.current.available);

    final after = _FakePlayerObject()..title = 'After restart';
    final afterClient = await _servePlayer(bus, after, 'fake');
    addTearDown(afterClient.close);
    await _waitFor(
      () =>
          service.current.available && service.current.title == 'After restart',
    );

    after.title = 'Signal after restart';
    await _emitUntil(after, <String, DBusValue>{
      'Metadata': after._metadata(),
    }, () => service.current.title == 'Signal after restart');
  });

  test(
    'paused recovery keeps signals live and resumes with one scan',
    () async {
      final bus = await _FakeBus.start();
      addTearDown(bus.dispose);
      final service = _service(
        bus,
        recoveryInterval: const Duration(milliseconds: 80),
      );
      addTearDown(service.dispose);
      await service.start();

      final player = _FakePlayerObject();
      final client = await _servePlayer(bus, player, 'fake');
      addTearDown(client.close);
      await _waitFor(() => service.current.available);

      service.pauseRecovery();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final pausedReads = player.playerGetAllCalls;
      await Future<void>.delayed(const Duration(milliseconds: 240));
      expect(
        player.playerGetAllCalls,
        pausedReads,
        reason: 'the recovery timer is cancelled while idle',
      );

      player.title = 'Signal while paused';
      player.playbackStatus = 'Paused';
      await _emitUntil(player, <String, DBusValue>{
        'Metadata': player._metadata(),
        'PlaybackStatus': DBusString('Paused'),
      }, () => service.current.title == 'Signal while paused');
      expect(service.current.playing, isFalse);
      expect(
        player.playerGetAllCalls,
        pausedReads,
        reason: 'signal updates do not run a recovery scan',
      );

      player.title = 'Recovered on resume';
      final beforeResume = player.playerGetAllCalls;
      await service.resumeRecovery();
      expect(
        player.playerGetAllCalls,
        beforeResume + 1,
        reason: 'resume performs exactly one immediate scan',
      );
      expect(service.current.title, 'Recovered on resume');

      final afterResume = player.playerGetAllCalls;
      await _waitFor(() => player.playerGetAllCalls > afterResume);
    },
  );

  test('a repeated resume does not stack recovery timers', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = _service(
      bus,
      recoveryInterval: const Duration(milliseconds: 100),
    );
    addTearDown(service.dispose);
    await service.start();

    final player = _FakePlayerObject();
    final client = await _servePlayer(bus, player, 'fake');
    addTearDown(client.close);
    await _waitFor(() => service.current.available);

    service.pauseRecovery();
    await service.resumeRecovery();
    final afterFirstResume = player.playerGetAllCalls;

    await service.resumeRecovery();
    expect(
      player.playerGetAllCalls,
      afterFirstResume,
      reason: 'a second resume is a no-op',
    );

    await Future<void>.delayed(const Duration(milliseconds: 260));
    expect(
      player.playerGetAllCalls - afterFirstResume,
      inInclusiveRange(1, 3),
      reason: 'only one timer is armed',
    );
  });

  test('dispose while recovery is paused never revives the timer', () async {
    final bus = await _FakeBus.start();
    addTearDown(bus.dispose);
    final service = _service(
      bus,
      recoveryInterval: const Duration(milliseconds: 60),
    );
    addTearDown(service.dispose);
    await service.start();

    final player = _FakePlayerObject();
    final client = await _servePlayer(bus, player, 'fake');
    addTearDown(client.close);
    await _waitFor(() => service.current.available);

    service.pauseRecovery();
    await service.dispose();
    final disposedReads = player.playerGetAllCalls;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(player.playerGetAllCalls, disposedReads);

    await service.resumeRecovery();
    await Future<void>.delayed(const Duration(milliseconds: 140));
    expect(player.playerGetAllCalls, disposedReads);
  });

  test('starts while the bus is down and recovers when it appears', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-mpris');
    addTearDown(() => directory.delete(recursive: true));
    final address = DBusAddress.unix(path: '${directory.path}/bus');
    final service = MediaPlayerService(
      clientFactory: () => DBusClient(address),
      readTimeout: const Duration(seconds: 2),
      signalCoalesce: const Duration(milliseconds: 10),
      unavailableGrace: const Duration(milliseconds: 80),
      recoveryInterval: const Duration(milliseconds: 20),
      recoveryBackoff: const <Duration>[Duration(milliseconds: 10)],
    );
    addTearDown(service.dispose);
    await service.start();
    expect(service.current.available, isFalse);

    final server = DBusServer();
    await server.listenAddress(address);
    addTearDown(server.close);
    final player = _FakePlayerObject()..title = 'Cold start song';
    final client = DBusClient(address);
    addTearDown(client.close);
    await client.registerObject(player);
    await client.requestName('${MediaPlayerService.servicePrefix}fake');

    await _waitFor(
      () =>
          service.current.available &&
          service.current.title == 'Cold start song',
    );
  });

  test('bounds retries and stops them after dispose', () async {
    final directory = await Directory.systemTemp.createTemp('trickster-mpris');
    addTearDown(() => directory.delete(recursive: true));
    final address = DBusAddress.unix(path: '${directory.path}/bus');
    var creates = 0;
    final service = MediaPlayerService(
      clientFactory: () {
        creates += 1;
        return DBusClient(address);
      },
      readTimeout: const Duration(seconds: 2),
      recoveryInterval: const Duration(hours: 1),
      recoveryBackoff: const <Duration>[
        Duration(milliseconds: 30),
        Duration(milliseconds: 60),
        Duration(milliseconds: 120),
      ],
    );
    await service.start();
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(creates, greaterThanOrEqualTo(3));
    expect(creates, lessThanOrEqualTo(6));

    await service.dispose();
    final afterDispose = creates;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(creates, afterDispose);
  });

  test('playback state json round-trips', () {
    final state = MprisPlaybackState(
      serviceName: 'org.mpris.MediaPlayer2.fake',
      identity: 'Fake Player',
      title: 'Test Song',
      artists: const <String>['Test Artist'],
      album: 'Test Album',
      artUrl: 'file:///tmp/cover.png',
      length: const Duration(microseconds: 180000000),
      position: const Duration(microseconds: 42000000),
      observedAt: DateTime.fromMillisecondsSinceEpoch(1234),
      status: MprisPlaybackStatus.paused,
      canGoNext: true,
      canGoPrevious: false,
      canPlay: true,
      canPause: false,
    );
    expect(MprisPlaybackState.fromJson(state.toJson()), state);
    expect(
      MprisPlaybackState.fromJson(<String, dynamic>{'status': 'bogus'}),
      MprisPlaybackState.unavailable(),
    );
  });
}
