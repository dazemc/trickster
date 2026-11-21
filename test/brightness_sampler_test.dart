import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/brightness.dart';

Directory _createRoot() {
  final root = Directory.systemTemp.createTempSync('trickster-brightness');
  addTearDown(() => root.deleteSync(recursive: true));
  return root;
}

void _device(
  Directory root,
  String name, {
  required int current,
  required int max,
  int? actual,
  String? type,
  String? scale,
}) {
  final directory = Directory('${root.path}/$name')
    ..createSync(recursive: true);
  File('${directory.path}/brightness').writeAsStringSync('$current\n');
  File('${directory.path}/max_brightness').writeAsStringSync('$max\n');
  if (actual != null) {
    File('${directory.path}/actual_brightness').writeAsStringSync('$actual\n');
  }
  if (type != null) {
    File('${directory.path}/type').writeAsStringSync('$type\n');
  }
  if (scale != null) {
    File('${directory.path}/scale').writeAsStringSync('$scale\n');
  }
}

typedef _Fixture = ({
  BrightnessSampler sampler,
  List<BrightnessSample> samples,
  Future<void> Function() dispose,
});

_Fixture _fixture(
  Directory root, {
  Duration interval = const Duration(hours: 1),
}) {
  final sampler = BrightnessSampler(
    interval: interval,
    backlightRoot: root.path,
  );
  final samples = <BrightnessSample>[];
  final subscription = sampler.snapshots.listen(samples.add);
  return (
    sampler: sampler,
    samples: samples,
    dispose: () async {
      await subscription.cancel();
      sampler.dispose();
    },
  );
}

void main() {
  testWidgets('prefers firmware over platform and raw', (tester) async {
    final root = _createRoot();
    _device(
      root,
      'acpi_video0',
      current: 80,
      max: 100,
      type: 'platform',
      scale: 'linear',
    );
    _device(root, 'raw0', current: 90, max: 100, type: 'raw', scale: 'linear');
    _device(
      root,
      'intel_backlight',
      current: 40,
      max: 100,
      actual: 42,
      type: 'firmware',
      scale: 'linear',
    );
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();

    expect(f.samples, hasLength(1));
    final sample = f.samples.single;
    expect(sample.device, 'intel_backlight');
    expect(sample.current, 40);
    expect(sample.max, 100);
    expect(sample.actual, 42);
    expect(sample.type, 'firmware');
    expect(sample.scale, 'linear');
    expect(sample.percent, 40);
    expect(f.sampler.isRunning, isTrue);
  });

  testWidgets('prefers a vendor interface over acpi_video within one type', (
    tester,
  ) async {
    final root = _createRoot();
    _device(root, 'acpi_video0', current: 70, max: 100, type: 'platform');
    _device(root, 'vendor_backlight', current: 55, max: 100, type: 'platform');
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();

    expect(f.samples.single.device, 'vendor_backlight');
    expect(f.samples.single.current, 55);
  });

  testWidgets('follows a symlinked device directory', (tester) async {
    final root = _createRoot();
    final target = Directory.systemTemp.createTempSync(
      'trickster-brightness-panel',
    );
    addTearDown(() {
      if (target.existsSync()) {
        target.deleteSync(recursive: true);
      }
    });
    File('${target.path}/brightness').writeAsStringSync('55\n');
    File('${target.path}/max_brightness').writeAsStringSync('100\n');
    File('${target.path}/type').writeAsStringSync('firmware\n');
    Link('${root.path}/intel_backlight').createSync(target.path);

    final f = _fixture(root);
    addTearDown(f.dispose);

    expect(
      BrightnessSampler.hasReadableDevice(backlightRoot: root.path),
      isTrue,
    );
    f.sampler.start();
    await tester.pump();

    expect(f.samples.single.device, 'intel_backlight');
    expect(f.samples.single.current, 55);
  });

  testWidgets('zero is a valid brightness, never absent', (tester) async {
    final root = _createRoot();
    _device(root, 'panel', current: 0, max: 100, type: 'firmware');
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();

    expect(f.samples, hasLength(1));
    expect(f.samples.single.current, 0);
    expect(f.samples.single.percent, 0);
    expect(f.samples.single.visible, isTrue);
    expect(f.sampler.isRunning, isTrue);
  });

  testWidgets('a zero maximum is unavailable, not zero brightness', (
    tester,
  ) async {
    final root = _createRoot();
    _device(root, 'panel', current: 50, max: 0, type: 'firmware');
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();

    expect(f.samples, isEmpty);
    expect(f.sampler.isRunning, isFalse);
  });

  testWidgets('missing files and malformed values emit no sample', (
    tester,
  ) async {
    final root = _createRoot();
    final missingMax = Directory('${root.path}/missing_max')
      ..createSync(recursive: true);
    File('${missingMax.path}/brightness').writeAsStringSync('40\n');

    final malformed = Directory('${root.path}/malformed')
      ..createSync(recursive: true);
    File('${malformed.path}/brightness').writeAsStringSync('nope\n');
    File('${malformed.path}/max_brightness').writeAsStringSync('100\n');

    final f = _fixture(root);
    addTearDown(f.dispose);
    f.sampler.start();
    await tester.pump();

    expect(f.samples, isEmpty);
    expect(f.sampler.isRunning, isFalse);
  });

  testWidgets('clamps a stored level above the maximum', (tester) async {
    final root = _createRoot();
    _device(root, 'panel', current: 140, max: 100, type: 'firmware');
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();

    expect(f.samples.single.current, 100);
    expect(f.samples.single.percent, 100);
  });

  testWidgets('a missing device stops the timer without a synthetic sample', (
    tester,
  ) async {
    final root = _createRoot();
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();

    expect(f.samples, isEmpty);
    expect(f.sampler.isActive, isTrue);
    expect(f.sampler.isRunning, isFalse);
  });

  testWidgets('refresh discovers a device that appeared after the first scan', (
    tester,
  ) async {
    final root = _createRoot();
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples, isEmpty);
    expect(f.sampler.isRunning, isFalse);

    _device(root, 'panel', current: 63, max: 100, type: 'firmware');
    f.sampler.refresh();
    await tester.pump();

    expect(f.samples, hasLength(1));
    expect(f.samples.single.current, 63);
    expect(f.sampler.isRunning, isTrue);
  });

  testWidgets('a disappeared device clears once and stops sampling', (
    tester,
  ) async {
    final root = _createRoot();
    _device(root, 'panel', current: 63, max: 100, type: 'firmware');
    final f = _fixture(root, interval: const Duration(seconds: 1));
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples.single.current, 63);
    expect(f.sampler.isRunning, isTrue);

    Directory('${root.path}/panel').deleteSync(recursive: true);
    await tester.pump(const Duration(seconds: 1));

    expect(f.samples, hasLength(2));
    expect(f.samples.last.current, isNull);
    expect(f.samples.last.device, isNull);
    expect(f.sampler.isRunning, isFalse);
  });

  testWidgets('identical samples are deduplicated', (tester) async {
    final root = _createRoot();
    _device(root, 'panel', current: 63, max: 100, type: 'firmware');
    final f = _fixture(root, interval: const Duration(seconds: 1));
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(f.samples, hasLength(1));
    expect(f.sampler.isRunning, isTrue);
  });

  testWidgets('pause holds the last sample; resume publishes the change', (
    tester,
  ) async {
    final root = _createRoot();
    _device(root, 'panel', current: 63, max: 100, type: 'firmware');
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.samples.single.current, 63);

    File('${root.path}/panel/brightness').writeAsStringSync('70\n');
    f.sampler.pause();
    expect(f.sampler.isRunning, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(f.samples, hasLength(1));

    f.sampler.resume();
    await tester.pump();
    expect(f.samples, hasLength(2));
    expect(f.samples.last.current, 70);
    expect(f.sampler.isRunning, isTrue);
  });

  testWidgets('refresh is ignored while paused', (tester) async {
    final root = _createRoot();
    final f = _fixture(root);
    addTearDown(f.dispose);

    f.sampler.start(paused: true);
    _device(root, 'panel', current: 63, max: 100, type: 'firmware');
    f.sampler.refresh();
    await tester.pump();
    expect(f.samples, isEmpty);

    f.sampler.resume();
    await tester.pump();
    expect(f.samples.single.current, 63);
  });

  test('dispose is idempotent and closes the stream', () async {
    final sampler = BrightnessSampler(
      interval: const Duration(hours: 1),
      backlightRoot: '/nonexistent/trickster-brightness',
    );
    final subscription = sampler.snapshots.listen((_) {});
    sampler.dispose();
    sampler.dispose();
    await subscription.cancel();

    expect(sampler.isRunning, isFalse);
    expect(sampler.isActive, isFalse);
  });
}
