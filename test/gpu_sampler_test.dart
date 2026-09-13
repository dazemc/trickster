import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/gpu.dart';

Directory _createRoot(Map<String, (String? vendor, String? busy)> cards) {
  final root = Directory.systemTemp.createTempSync('trickster-gpu');
  addTearDown(() => root.deleteSync(recursive: true));
  cards.forEach((name, card) {
    final device = Directory('${root.path}/$name/device')
      ..createSync(recursive: true);
    final vendor = card.$1;
    if (vendor != null) {
      File('${device.path}/vendor').writeAsStringSync(vendor);
    }
    final busy = card.$2;
    if (busy != null) {
      File('${device.path}/gpu_busy_percent').writeAsStringSync(busy);
    }
  });
  return root;
}

void main() {
  test('maps readable cards to stable ids, labels, and usages', () {
    final root = _createRoot({
      'card0': ('0x1002', '40'),
      'card1': ('0x8086', null),
      'card2': ('0x1002', '80'),
      'card3': ('0x10de', '10'),
    });
    final sampler = GpuSampler(drmRoot: root.path);
    addTearDown(sampler.dispose);

    final loads = sampler.sample();
    expect(loads.map((load) => load.id), ['card0', 'card2', 'card3']);
    expect(loads.map((load) => load.label), ['AMD0', 'AMD1', 'NV']);
    expect(loads.map((load) => load.usage), [0.4, 0.8, 0.1]);
    expect(loads.map((load) => load.history), [
      [0.4],
      [0.8],
      [0.1],
    ]);

    final again = sampler.sample();
    expect(again.map((load) => load.usage), [0.4, 0.8, 0.1]);
    expect(again.first.history, [0.4, 0.4]);
  });

  test('series keeps the cap and appends newest last', () {
    final root = _createRoot({'card0': ('0x1002', '0')});
    final sampler = GpuSampler(drmRoot: root.path);
    addTearDown(sampler.dispose);
    final busyFile = File('${root.path}/card0/device/gpu_busy_percent');

    late List<GpuLoad> loads;
    for (var i = 0; i < GpuLoad.capacity + 5; i++) {
      busyFile.writeAsStringSync('$i');
      loads = sampler.sample();
    }
    final load = loads.single;
    expect(load.history.length, GpuLoad.capacity);
    expect(load.history.first, closeTo(0.05, 1e-9));
    expect(load.history.last, closeTo(0.49, 1e-9));
    expect(load.usage, closeTo(0.49, 1e-9));
  });

  test('missing drm root yields an empty sample', () {
    final sampler = GpuSampler(drmRoot: '/nonexistent/trickster-drm');
    addTearDown(sampler.dispose);
    expect(sampler.sample(), isEmpty);
  });

  test('gpu load json round-trips', () {
    final load = const GpuLoad(id: 'card0', label: 'AMD')
        .append(0.4)
        .append(0.7);
    final decoded = GpuLoad.fromJson(Map<String, dynamic>.from(load.toJson()));
    expect(decoded, load);
  });
}
