import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/platform/layer_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/trickster-idle');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('idleSupported asks the native capability probe', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'idleSupported' ? true : false;
    });
    final shell = LayerShell(channel: channel);

    expect(await shell.idleSupported(), isTrue);
    expect(calls, ['idleSupported']);
  });

  test('seatIdle reads the cached native state', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'seatIdle';
    });
    final shell = LayerShell(channel: channel);

    expect(await shell.seatIdle(), isTrue);
    expect(calls, ['seatIdle']);
  });

  test('absent and failed native answers fall back to false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    final shell = LayerShell(channel: channel);
    expect(await shell.idleSupported(), isFalse);
    expect(await shell.seatIdle(), isFalse);

    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw StateError('channel closed'),
    );
    expect(await shell.idleSupported(), isFalse);
    expect(await shell.seatIdle(), isFalse);
  });

  test('platform idle and blur messages fan out to every listener', () async {
    // The production channel installs the one shared method handler.
    LayerShell();
    final first = <bool>[];
    final second = <bool>[];
    final blur = <bool>[];
    final firstSubscription = LayerShell.seatIdleChanges.listen(first.add);
    final secondSubscription = LayerShell.seatIdleChanges.listen(second.add);
    final blurSubscription = LayerShell.blurChanges.listen(blur.add);
    addTearDown(firstSubscription.cancel);
    addTearDown(secondSubscription.cancel);
    addTearDown(blurSubscription.cancel);

    Future<void> deliver(String method, Object? arguments) {
      return messenger.handlePlatformMessage(
        'org.trickster.bar/layer_shell',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
    }

    await deliver('idleChanged', true);
    await deliver('idleChanged', false);
    await deliver('blurChanged', true);
    // Wrong argument types and unknown methods are ignored.
    await deliver('idleChanged', 'not-a-bool');
    await deliver('blurChanged', 1);
    await deliver('unrelated', true);
    await pumpEventQueue();

    expect(first, [true, false]);
    expect(second, [true, false]);
    expect(blur, [true]);
  });
}
