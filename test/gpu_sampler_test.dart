import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/nvidia.dart';

Directory _createRoot(
  Map<String, (String? vendor, String? busy)> cards, {
  Map<String, String> runtimeStatus = const {},
}) {
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
    final status = runtimeStatus[name];
    if (status != null) {
      Directory('${device.path}/power').createSync(recursive: true);
      File('${device.path}/power/runtime_status').writeAsStringSync(status);
    }
  });
  return root;
}

class FakeNvmlReader extends NvmlReader {
  FakeNvmlReader([this.samples = const []]);

  final List<NvidiaGpuSample> samples;
  var reads = 0;

  @override
  Future<List<NvidiaGpuSample>> read() async {
    reads += 1;
    return samples;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('maps readable cards to stable ids, labels, and usages', () async {
    final root = _createRoot({
      'card0': ('0x1002', '40'),
      'card1': ('0x8086', null),
      'card2': ('0x1002', '80'),
      'card3': ('0x10de', '10'),
    });
    final sampler = GpuSampler(drmRoot: root.path, nvml: FakeNvmlReader());
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(loads.map((load) => load.id), ['card0', 'card2', 'card3']);
    expect(loads.map((load) => load.label), ['AMD0', 'AMD1', 'GPU']);
    expect(loads.map((load) => load.usage), [0.4, 0.8, 0.1]);
    expect(loads.map((load) => load.history), [
      [0.4],
      [0.8],
      [0.1],
    ]);

    final again = await sampler.sample();
    expect(again.map((load) => load.usage), [0.4, 0.8, 0.1]);
    expect(again.first.history, [0.4, 0.4]);
  });

  test('series keeps the cap and appends newest last', () async {
    final root = _createRoot({'card0': ('0x1002', '0')});
    final sampler = GpuSampler(drmRoot: root.path, nvml: FakeNvmlReader());
    addTearDown(sampler.dispose);
    final busyFile = File('${root.path}/card0/device/gpu_busy_percent');

    late List<GpuLoad> loads;
    for (var i = 0; i < GpuLoad.capacity + 5; i++) {
      busyFile.writeAsStringSync('$i');
      loads = await sampler.sample();
    }
    final load = loads.single;
    expect(load.history.length, GpuLoad.capacity);
    expect(load.history.first, closeTo(0.05, 1e-9));
    expect(load.history.last, closeTo(0.49, 1e-9));
    expect(load.usage, closeTo(0.49, 1e-9));
  });

  test('missing drm root yields an empty sample', () async {
    final sampler = GpuSampler(
      drmRoot: '/nonexistent/trickster-drm',
      nvml: FakeNvmlReader(),
    );
    addTearDown(sampler.dispose);
    expect(await sampler.sample(), isEmpty);
  });

  test('merges NVML readings with stable nvml ids', () async {
    final root = _createRoot({'card0': ('0x1002', '40')});
    final nvml = FakeNvmlReader(const [
      NvidiaGpuSample(index: 0, usage: 0.3),
      NvidiaGpuSample(index: 1, usage: 0.6),
    ]);
    final sampler = GpuSampler(drmRoot: root.path, nvml: nvml);
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(loads.map((load) => load.id), ['card0', 'nvml0', 'nvml1']);
    expect(loads.map((load) => load.label), ['AMD', 'GPU0', 'GPU1']);
    expect(loads.map((load) => load.usage), [0.4, 0.3, 0.6]);
    expect(nvml.reads, 1);
  });

  test('leaves a runtime-suspended NVIDIA GPU asleep', () async {
    final root = _createRoot(
      {'card1': ('0x10de', null)},
      runtimeStatus: {'card1': 'suspended'},
    );
    final nvml = FakeNvmlReader(const [
      NvidiaGpuSample(index: 0, usage: 0.9),
    ]);
    final sampler = GpuSampler(drmRoot: root.path, nvml: nvml);
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(nvml.reads, 0);
    expect(loads.single.id, 'nvml0');
    expect(loads.single.label, 'GPU');
    expect(loads.single.usage, 0.0);
  });

  test('reads NVML when the NVIDIA GPU is active', () async {
    final root = _createRoot(
      {'card1': ('0x10de', null)},
      runtimeStatus: {'card1': 'active'},
    );
    final nvml = FakeNvmlReader(const [
      NvidiaGpuSample(index: 0, usage: 0.9),
    ]);
    final sampler = GpuSampler(drmRoot: root.path, nvml: nvml);
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(nvml.reads, 1);
    expect(loads.single.id, 'nvml0');
    expect(loads.single.usage, 0.9);
  });

  test('gpu load json round-trips', () {
    final load = const GpuLoad(id: 'card0', label: 'AMD')
        .append(0.4)
        .append(0.7);
    final decoded = GpuLoad.fromJson(Map<String, dynamic>.from(load.toJson()));
    expect(decoded, load);
  });
}
