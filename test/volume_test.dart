import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/volume.dart';

const _channel = MethodChannel('test/volume');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return call.method == 'volumeStart';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  Future<void> deliver(Object? arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('volume', arguments),
          ),
          (_) {},
        );
  }

  test('start and stop drive the native methods once', () async {
    final volume = PipeWireVolume(channel: _channel);
    addTearDown(volume.dispose);

    expect(await volume.start(), isTrue);
    expect(volume.isRunning, isTrue);
    expect(calls.map((call) => call.method), ['volumeStart']);

    expect(await volume.start(), isTrue);
    expect(calls, hasLength(1));

    await volume.stop();
    expect(volume.isRunning, isFalse);
    expect(calls.map((call) => call.method), ['volumeStart', 'volumeStop']);

    await volume.stop();
    expect(calls, hasLength(2));
  });

  test('a refused start leaves the watcher stopped', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return false;
        });
    final volume = PipeWireVolume(channel: _channel);
    addTearDown(volume.dispose);

    expect(await volume.start(), isFalse);
    expect(volume.isRunning, isFalse);
  });

  test('readings parse into sink volumes', () async {
    final volume = PipeWireVolume(channel: _channel);
    addTearDown(volume.dispose);
    await volume.start();

    final next = volume.levels.first;
    await deliver(<String, Object>{'volume': 0.4, 'muted': false});

    final reading = await next;
    expect(reading.volume, closeTo(0.4, 0.0001));
    expect(reading.muted, isFalse);
  });

  test('the first reading is replayed to a late listener', () async {
    final volume = PipeWireVolume(channel: _channel);
    addTearDown(volume.dispose);
    await volume.start();
    // The runner pushes before anything listens.
    await deliver(<String, Object>{'volume': 0.4, 'muted': false});

    final reading = await volume.levels.first;
    expect(reading.volume, closeTo(0.4, 0.0001));
  });

  test('readings are ignored while stopped and when malformed', () async {
    final volume = PipeWireVolume(channel: _channel);
    addTearDown(volume.dispose);
    final seen = <SinkVolume>[];
    volume.levels.listen(seen.add);

    // Stopped: buffered for the start handshake, not emitted yet.
    await deliver(<String, Object>{'volume': 0.4, 'muted': false});
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);

    // Starting delivers the buffered reading.
    await volume.start();
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));

    await deliver(<String, Object>{'volume': 'loud', 'muted': false});
    await deliver('not a map');
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
  });

  test('set clamps and forwards to the native side', () async {
    final volume = PipeWireVolume(channel: _channel);
    addTearDown(volume.dispose);
    await volume.start();

    await volume.set(0.7);
    await volume.set(1.4);

    final sets = calls.where((call) => call.method == 'volumeSet').toList();
    expect(sets, hasLength(2));
    expect(sets[0].arguments, <String, Object?>{'volume': 0.7});
    expect(sets[1].arguments, <String, Object?>{'volume': 1.0});
  });
}
