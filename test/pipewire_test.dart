import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/pipewire.dart';

const _channel = MethodChannel('test/pipewire');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return call.method == 'pipewireStart';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// Delivers a frame call to the capture's handler.
  Future<void> deliver(Object? arguments) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('frame', arguments),
          ),
          (_) {},
        );
  }

  test('start and stop drive the native methods once', () async {
    final capture = PipeWireCapture(channel: _channel);
    addTearDown(capture.dispose);

    expect(await capture.start(), isTrue);
    expect(capture.isRunning, isTrue);
    expect(calls.map((call) => call.method), ['pipewireStart']);

    // Already running: no second platform call.
    expect(await capture.start(), isTrue);
    expect(calls, hasLength(1));

    await capture.stop();
    expect(capture.isRunning, isFalse);
    expect(calls.map((call) => call.method), ['pipewireStart', 'pipewireStop']);

    // Already stopped: no second platform call.
    await capture.stop();
    expect(calls, hasLength(2));
  });

  test('a refused start leaves the capture stopped', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return false;
        });
    final capture = PipeWireCapture(channel: _channel);
    addTearDown(capture.dispose);

    expect(await capture.start(), isFalse);
    expect(capture.isRunning, isFalse);
  });

  test('frames parse into interleaved F32 batches', () async {
    final capture = PipeWireCapture(channel: _channel);
    addTearDown(capture.dispose);
    await capture.start();

    final frame = capture.frames.firstWhere((_) => true);
    final samples = Float32List.fromList(<double>[0.5, -0.5, 0.25, -0.25]);
    await deliver(<String, Object>{
      'data': samples.buffer.asUint8List(),
      'rate': 44100,
      'channels': 2,
    });

    final received = await frame;
    expect(received.rate, 44100);
    expect(received.channels, 2);
    expect(received.frames, 2);
    expect(received.samples, samples);
  });

  test('frames are ignored while stopped and when malformed', () async {
    final capture = PipeWireCapture(channel: _channel);
    addTearDown(capture.dispose);
    final seen = <PipeWireFrame>[];
    capture.frames.listen(seen.add);

    await deliver(<String, Object>{
      'data': Uint8List(8),
      'rate': 48000,
      'channels': 2,
    });
    await capture.start();
    await deliver(<String, Object>{
      'data': Uint8List(4),
      'rate': 48000,
      'channels': 2,
    });
    await deliver(<String, Object>{
      'data': Uint8List(16),
      'rate': 48000,
      'channels': 0,
    });
    await deliver('not a map');
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
  });
}
