import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/gpu.dart';
import 'package:trickster/src/services/nvidia.dart';

Directory _createRoot(
  Map<String, (String? vendor, String? busy)> cards, {
  Map<String, String> runtimeStatus = const {},
  bool nvidiaDriver = true,
}) {
  final root = Directory.systemTemp.createTempSync('trickster-gpu');
  addTearDown(() => root.deleteSync(recursive: true));
  if (nvidiaDriver) {
    File(_driverPath(root)).writeAsStringSync('NVRM version');
  }
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

String _driverPath(Directory root) => '${root.path}/nvidia-version';

void _writeDeviceFile(
  Directory root,
  String card,
  String relative,
  String value,
) {
  File('${root.path}/$card/device/$relative')
    ..createSync(recursive: true)
    ..writeAsStringSync(value);
}

class FakeNvmlReader extends NvmlReader {
  FakeNvmlReader([this.samples = const [], this.error]);

  final List<NvidiaGpuSample> samples;
  final String? error;
  var reads = 0;
  bool? includeUsage;
  bool? includeMemory;

  @override
  Future<NvmlRead> read({
    bool includeUsage = true,
    bool includeMemory = true,
  }) async {
    reads += 1;
    this.includeUsage = includeUsage;
    this.includeMemory = includeMemory;
    return (samples: samples, error: error);
  }

  @override
  Future<void> dispose() async {}
}

/// One NVML read at a time, held open until the test completes it. This is
/// how the pause/resume generation is exercised without timing luck.
class BlockingNvmlReader extends NvmlReader {
  Completer<NvmlRead>? _pending;
  var reads = 0;
  var disposed = 0;
  var active = 0;
  var maxActive = 0;
  bool? includeUsage;
  bool? includeMemory;

  bool get hasPending => _pending != null;

  @override
  Future<NvmlRead> read({bool includeUsage = true, bool includeMemory = true}) {
    reads += 1;
    this.includeUsage = includeUsage;
    this.includeMemory = includeMemory;
    active += 1;
    if (active > maxActive) {
      maxActive = active;
    }
    final pending = Completer<NvmlRead>();
    _pending = pending;
    return pending.future.whenComplete(() => active -= 1);
  }

  void complete(List<NvidiaGpuSample> samples, {String? error}) {
    final pending = _pending;
    _pending = null;
    pending?.complete((samples: samples, error: error));
  }

  @override
  Future<void> dispose() async {
    disposed += 1;
  }
}

typedef _GpuFixture = ({
  GpuSampler sampler,
  BlockingNvmlReader nvml,
  List<List<GpuLoad>> samples,
  Future<void> Function() dispose,
});

_GpuFixture _blockingFixture({Duration interval = const Duration(hours: 1)}) {
  final root = _createRoot(const {});
  final nvml = BlockingNvmlReader();
  final sampler = GpuSampler(
    interval: interval,
    drmRoot: root.path,
    nvml: nvml,
    nvidiaDriverPath: _driverPath(root),
  );
  final samples = <List<GpuLoad>>[];
  final subscription = sampler.snapshots.listen(samples.add);
  return (
    sampler: sampler,
    nvml: nvml,
    samples: samples,
    dispose: () async {
      await subscription.cancel();
      await sampler.dispose();
    },
  );
}

const _blockingSample = [NvidiaGpuSample(index: 0, usage: 0.4, name: 'RTX')];

void main() {
  test('maps readable cards to stable ids, labels, and usages', () async {
    final root = _createRoot({
      'card0': ('0x1002', '40'),
      'card1': ('0x8086', null),
      'card2': ('0x1002', '80'),
      'card3': ('0x10de', '10'),
    });
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: FakeNvmlReader(),
      nvidiaDriverPath: _driverPath(root),
    );
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

  test('maps dedicated VRAM bytes and keeps a memory series', () async {
    final root = _createRoot({'card0': ('0x1002', '40')});
    _writeDeviceFile(root, 'card0', 'mem_info_vram_total', '1000');
    _writeDeviceFile(root, 'card0', 'mem_info_vram_used', '250');
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: FakeNvmlReader(),
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(loads.single.usage, closeTo(0.4, 1e-9));
    expect(loads.single.memoryUsedBytes, 250);
    expect(loads.single.memoryTotalBytes, 1000);
    expect(loads.single.memoryFraction, closeTo(0.25, 1e-9));
    expect(loads.single.memoryHistory, [0.25]);

    _writeDeviceFile(root, 'card0', 'mem_info_vram_used', '500');
    final again = await sampler.sample();
    expect(again.single.memoryFraction, closeTo(0.5, 1e-9));
    expect(again.single.memoryHistory, [0.25, 0.5]);
  });

  test('reads VRAM on a memory-only card', () async {
    final root = _createRoot({'card0': ('0x1002', null)});
    _writeDeviceFile(root, 'card0', 'mem_info_vram_total', '2000');
    _writeDeviceFile(root, 'card0', 'mem_info_vram_used', '500');
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: FakeNvmlReader(),
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(loads, hasLength(1));
    expect(loads.single.id, 'card0');
    expect(loads.single.usage, isNull);
    expect(loads.single.memoryUsedBytes, 500);
    expect(loads.single.memoryTotalBytes, 2000);
    expect(loads.single.memoryFraction, closeTo(0.25, 1e-9));
  });

  test(
    'memory-only and busy-only cards keep their independent fields',
    () async {
      final root = _createRoot({
        'card0': ('0x1002', '40'),
        'card1': ('0x8086', null),
      });
      _writeDeviceFile(root, 'card1', 'mem_info_vram_total', '2000');
      _writeDeviceFile(root, 'card1', 'mem_info_vram_used', '1000');
      final sampler = GpuSampler(
        drmRoot: root.path,
        nvml: FakeNvmlReader(),
        nvidiaDriverPath: _driverPath(root),
      );
      addTearDown(sampler.dispose);

      final loads = await sampler.sample();
      expect(loads.map((load) => load.id), ['card0', 'card1']);
      expect(loads.first.usage, closeTo(0.4, 1e-9));
      expect(loads.first.memoryFraction, isNull);
      expect(loads.last.usage, isNull);
      expect(loads.last.memoryFraction, closeTo(0.5, 1e-9));
    },
  );

  test('zero, missing, or unreadable memory is no VRAM', () async {
    final root = _createRoot({
      'card0': ('0x1002', '40'),
      'card1': ('0x8086', null),
    });
    _writeDeviceFile(root, 'card0', 'mem_info_vram_total', '0');
    _writeDeviceFile(root, 'card0', 'mem_info_vram_used', '0');
    _writeDeviceFile(root, 'card1', 'mem_info_vram_total', '2000');
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: FakeNvmlReader(),
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(loads, hasLength(1), reason: 'the zero/missing card is skipped');
    expect(loads.single.id, 'card0');
    expect(loads.single.memoryFraction, isNull);
  });

  test('usage and memory flags gate independent reads', () async {
    final root = _createRoot({'card0': ('0x1002', '40')});
    _writeDeviceFile(root, 'card0', 'mem_info_vram_total', '1000');
    _writeDeviceFile(root, 'card0', 'mem_info_vram_used', '250');
    final nvml = FakeNvmlReader();
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: nvml,
      nvidiaDriverPath: _driverPath(root),
      includeUsage: false,
      includeMemory: true,
    );
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(loads.single.usage, isNull);
    expect(loads.single.memoryFraction, closeTo(0.25, 1e-9));
    expect(nvml.includeUsage, isFalse);
    expect(nvml.includeMemory, isTrue);

    final memoryOnlyRoot = _createRoot({'card0': ('0x8086', null)});
    _writeDeviceFile(memoryOnlyRoot, 'card0', 'mem_info_vram_total', '1000');
    _writeDeviceFile(memoryOnlyRoot, 'card0', 'mem_info_vram_used', '250');
    final usageNvml = FakeNvmlReader();
    final usageOnly = GpuSampler(
      drmRoot: memoryOnlyRoot.path,
      nvml: usageNvml,
      nvidiaDriverPath: _driverPath(memoryOnlyRoot),
      includeUsage: true,
      includeMemory: false,
    );
    addTearDown(usageOnly.dispose);
    expect(await usageOnly.sample(), isEmpty);
    expect(usageNvml.includeUsage, isTrue);
    expect(usageNvml.includeMemory, isFalse);
  });

  test('configure re-discovers the newly enabled fields', () async {
    final root = _createRoot({'card0': ('0x1002', '40')});
    _writeDeviceFile(root, 'card0', 'mem_info_vram_total', '1000');
    _writeDeviceFile(root, 'card0', 'mem_info_vram_used', '250');
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: FakeNvmlReader(),
      nvidiaDriverPath: _driverPath(root),
      includeUsage: true,
      includeMemory: false,
    );
    addTearDown(sampler.dispose);

    final usageOnly = await sampler.sample();
    expect(usageOnly.single.usage, closeTo(0.4, 1e-9));
    expect(usageOnly.single.memoryFraction, isNull);

    sampler.configure(includeUsage: true, includeMemory: true);
    final both = await sampler.sample();
    expect(both.single.usage, closeTo(0.4, 1e-9));
    expect(both.single.memoryFraction, closeTo(0.25, 1e-9));

    sampler.configure(includeUsage: false, includeMemory: true);
    final memoryOnly = await sampler.sample();
    expect(memoryOnly.single.usage, isNull);
    expect(memoryOnly.single.memoryFraction, closeTo(0.25, 1e-9));
  });

  test('the memory series keeps the cap and appends newest last', () async {
    final root = _createRoot({'card0': ('0x1002', '40')});
    _writeDeviceFile(root, 'card0', 'mem_info_vram_total', '100');
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: FakeNvmlReader(),
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    late List<GpuLoad> loads;
    for (var i = 0; i < GpuLoad.capacity + 5; i += 1) {
      _writeDeviceFile(root, 'card0', 'mem_info_vram_used', '$i');
      loads = await sampler.sample();
    }
    final load = loads.single;
    expect(load.memoryHistory.length, GpuLoad.capacity);
    expect(load.memoryHistory.first, closeTo(0.05, 1e-9));
    expect(load.memoryHistory.last, closeTo(0.49, 1e-9));
  });

  test('backward-compatible GPU JSON loads without memory keys', () {
    final old = GpuLoad.fromJson(const <String, dynamic>{
      'id': 'card0',
      'label': 'AMD',
      'usage': 0.4,
      'history': [0.4],
    });
    expect(old.memoryUsedBytes, isNull);
    expect(old.memoryTotalBytes, isNull);
    expect(old.memoryFraction, isNull);
    expect(old.memoryHistory, isEmpty);

    const load = GpuLoad(
      id: 'card0',
      label: 'AMD',
      usage: 0.4,
      memoryUsedBytes: 500,
      memoryTotalBytes: 1000,
      memoryHistory: [0.5],
    );
    final decoded = GpuLoad.fromJson(Map<String, dynamic>.from(load.toJson()));
    expect(decoded.memoryUsedBytes, 500);
    expect(decoded.memoryTotalBytes, 1000);
    expect(decoded.memoryFraction, 0.5);
    expect(decoded.memoryHistory, [0.5]);
  });

  test('hasGpuMemorySource recognizes NVIDIA, sysfs, and absent memory', () {
    final nvidia = _createRoot({});
    expect(
      hasGpuMemorySource(
        drmRoot: nvidia.path,
        nvidiaDriverPath: _driverPath(nvidia),
      ),
      isTrue,
    );

    final amd = _createRoot({'card0': ('0x1002', null)}, nvidiaDriver: false);
    _writeDeviceFile(amd, 'card0', 'mem_info_vram_total', '1000');
    _writeDeviceFile(amd, 'card0', 'mem_info_vram_used', '250');
    expect(
      hasGpuMemorySource(drmRoot: amd.path, nvidiaDriverPath: _driverPath(amd)),
      isTrue,
    );

    final none = _createRoot({'card0': ('0x8086', '20')}, nvidiaDriver: false);
    expect(
      hasGpuMemorySource(
        drmRoot: none.path,
        nvidiaDriverPath: _driverPath(none),
      ),
      isFalse,
    );
  });

  test(
    'follows symlinked DRM card entries in discovery and availability',
    () async {
      final root = Directory.systemTemp.createTempSync('trickster-gpu-symlink');
      addTearDown(() => root.deleteSync(recursive: true));
      final target = Directory('${root.path}/physical-card/device')
        ..createSync(recursive: true);
      File('${target.path}/vendor').writeAsStringSync('0x1002\n');
      File('${target.path}/gpu_busy_percent').writeAsStringSync('40\n');
      File('${target.path}/mem_info_vram_total').writeAsStringSync('1000\n');
      File('${target.path}/mem_info_vram_used').writeAsStringSync('250\n');
      Link('${root.path}/card0').createSync('${root.path}/physical-card');

      final sampler = GpuSampler(
        drmRoot: root.path,
        nvml: FakeNvmlReader(),
        nvidiaDriverPath: '${root.path}/missing-nvidia-version',
      );
      addTearDown(sampler.dispose);

      final loads = await sampler.sample();
      expect(loads, hasLength(1));
      expect(loads.single.id, 'card0');
      expect(loads.single.usage, closeTo(0.4, 1e-9));
      expect(loads.single.memoryFraction, closeTo(0.25, 1e-9));
      expect(
        hasGpuMemorySource(
          drmRoot: root.path,
          nvidiaDriverPath: '${root.path}/missing-nvidia-version',
        ),
        isTrue,
      );
    },
  );

  test('real sysfs card symlinks are traversed when a source is present', () {
    final root = Directory('/sys/class/drm');
    if (!root.existsSync()) {
      return;
    }
    final cards = root
        .listSync(followLinks: false)
        .whereType<Link>()
        .where(
          (link) => RegExp(r'^card\d+$').hasMatch(
            link.uri.pathSegments.where((part) => part.isNotEmpty).last,
          ),
        )
        .toList(growable: false);
    if (cards.isEmpty) {
      return;
    }
    final hasSource = cards.any((card) {
      final device = '${card.path}/device';
      if (File('$device/mem_info_vram_total').existsSync() &&
          File('$device/mem_info_vram_used').existsSync()) {
        return true;
      }
      final vendor = File('$device/vendor');
      return vendor.existsSync() &&
          vendor.readAsStringSync().trim() == '0x10de';
    });
    if (!hasSource) {
      return;
    }
    expect(
      hasGpuMemorySource(
        drmRoot: root.path,
        nvidiaDriverPath: '/nonexistent/trickster-nvidia-version',
      ),
      isTrue,
    );
  });

  test('series keeps the cap and appends newest last', () async {
    final root = _createRoot({'card0': ('0x1002', '0')});
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: FakeNvmlReader(),
      nvidiaDriverPath: _driverPath(root),
    );
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
      nvidiaDriverPath: '/nonexistent/trickster-nvidia-version',
    );
    addTearDown(sampler.dispose);
    expect(await sampler.sample(), isEmpty);
  });

  test('skips NVML when no NVIDIA driver or card is present', () async {
    final root = _createRoot({}, nvidiaDriver: false);
    final nvml = FakeNvmlReader(const [NvidiaGpuSample(index: 0, usage: 0.9)]);
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: nvml,
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    expect(await sampler.sample(), isEmpty);
    expect(nvml.reads, 0);
  });

  test(
    'a discovered NVIDIA card opens the gate without the proc file',
    () async {
      final root = _createRoot(
        {'card1': ('0x10de', null)},
        runtimeStatus: {'card1': 'active'},
        nvidiaDriver: false,
      );
      final nvml = FakeNvmlReader(const [
        NvidiaGpuSample(index: 0, usage: 0.9),
      ]);
      final sampler = GpuSampler(
        drmRoot: root.path,
        nvml: nvml,
        nvidiaDriverPath: _driverPath(root),
      );
      addTearDown(sampler.dispose);

      final loads = await sampler.sample();
      expect(nvml.reads, 1);
      expect(loads.single.id, 'nvml0');
    },
  );

  test('a failed NVML stack logs one line and sampling continues', () async {
    final root = _createRoot({'card3': ('0x10de', null)});
    final logs = <String>[];
    final nvml = FakeNvmlReader(
      const [],
      'NVML driver/library version mismatch',
    );
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: nvml,
      nvidiaDriverPath: _driverPath(root),
      log: logs.add,
    );
    addTearDown(sampler.dispose);

    expect(await sampler.sample(), isEmpty);
    expect(await sampler.sample(), isEmpty);
    expect(nvml.reads, 2);
    // One line for the process, not one per sample.
    expect(logs, hasLength(1));
    expect(logs.single, contains('driver/library version mismatch'));
  });

  test('merges NVML readings with stable nvml ids', () async {
    final root = _createRoot({'card0': ('0x1002', '40')});
    final nvml = FakeNvmlReader(const [
      NvidiaGpuSample(index: 0, usage: 0.3, name: 'RTX 4070 Ti'),
      NvidiaGpuSample(index: 1, usage: 0.6),
    ]);
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: nvml,
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(loads.map((load) => load.id), ['card0', 'nvml0', 'nvml1']);
    expect(loads.map((load) => load.label), ['AMD', 'GPU0', 'GPU1']);
    expect(loads.map((load) => load.name), [null, 'RTX 4070 Ti', null]);
    expect(loads.map((load) => load.usage), [0.4, 0.3, 0.6]);
    expect(nvml.reads, 1);
  });

  test('queried names survive duplicate-label suffixes', () async {
    final root = _createRoot({});
    final nvml = FakeNvmlReader(const [
      NvidiaGpuSample(index: 0, usage: 0.3, name: 'RTX 4070 Ti'),
      NvidiaGpuSample(index: 1, usage: 0.6, name: 'RTX 4070 Ti'),
    ]);
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: nvml,
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(loads.map((load) => load.label), ['GPU0', 'GPU1']);
    expect(loads.map((load) => load.name), ['RTX 4070 Ti', 'RTX 4070 Ti']);
  });

  test('leaves a runtime-suspended NVIDIA GPU asleep', () async {
    final root = _createRoot(
      {'card1': ('0x10de', null)},
      runtimeStatus: {'card1': 'suspended'},
    );
    final nvml = FakeNvmlReader(const [
      NvidiaGpuSample(index: 0, usage: 0.9, usedBytes: 500, totalBytes: 1000),
    ]);
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: nvml,
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(nvml.reads, 0);
    expect(loads.single.id, 'nvml0');
    expect(loads.single.label, 'GPU');
    expect(loads.single.usage, 0.0);
    expect(loads.single.memoryFraction, isNull);
  });

  test(
    'does not fabricate zero for an active card beside a suspended one',
    () async {
      final root = _createRoot(
        {'card0': ('0x10de', null), 'card1': ('0x10de', null)},
        runtimeStatus: {'card0': 'active', 'card1': 'suspended'},
      );
      final nvml = FakeNvmlReader(const [
        NvidiaGpuSample(index: 0, usage: 0.9, name: 'RTX 4070 Ti'),
      ]);
      final sampler = GpuSampler(
        drmRoot: root.path,
        nvml: nvml,
        nvidiaDriverPath: _driverPath(root),
      );
      addTearDown(sampler.dispose);

      final loads = await sampler.sample();
      expect(nvml.reads, 0);
      expect(loads, hasLength(1));
      expect(loads.single.id, 'nvml1');
      expect(loads.single.usage, 0.0);
    },
  );

  test('refreshes a missing NVIDIA name when the card wakes', () async {
    final root = _createRoot(
      {'card0': ('0x10de', null)},
      runtimeStatus: {'card0': 'suspended'},
    );
    final nvml = FakeNvmlReader(const [
      NvidiaGpuSample(index: 0, usage: 0.9, name: 'RTX 4070 Ti'),
    ]);
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: nvml,
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    final first = await sampler.sample();
    expect(first.single.name, isNull);

    File(
      '${root.path}/card0/device/power/runtime_status',
    ).writeAsStringSync('active');
    final second = await sampler.sample();
    expect(nvml.reads, 1);
    expect(second.single.name, 'RTX 4070 Ti');
    expect(second.single.usage, closeTo(0.9, 1e-9));
    expect(second.single.history, [0.0, 0.9]);
  });

  test('reads NVML when the NVIDIA GPU is active', () async {
    final root = _createRoot(
      {'card1': ('0x10de', null)},
      runtimeStatus: {'card1': 'active'},
    );
    final nvml = FakeNvmlReader(const [
      NvidiaGpuSample(index: 0, usage: 0.9, name: 'RTX 4070 Ti'),
    ]);
    final sampler = GpuSampler(
      drmRoot: root.path,
      nvml: nvml,
      nvidiaDriverPath: _driverPath(root),
    );
    addTearDown(sampler.dispose);

    final loads = await sampler.sample();
    expect(nvml.reads, 1);
    expect(loads.single.id, 'nvml0');
    expect(loads.single.label, 'GPU');
    expect(loads.single.name, 'RTX 4070 Ti');
    expect(loads.single.usage, 0.9);
  });

  testWidgets(
    'pause drops the in-flight read and resume takes one fresh sample',
    (tester) async {
      final f = _blockingFixture();
      addTearDown(f.dispose);

      f.sampler.start();
      expect(f.sampler.isRunning, isTrue);
      await tester.pump();
      expect(f.nvml.reads, 1);

      f.sampler.pause();
      expect(f.sampler.isRunning, isFalse);
      f.sampler.pause();
      f.nvml.complete(_blockingSample);
      await tester.pump();
      expect(f.samples, isEmpty);

      f.sampler.resume();
      expect(f.sampler.isRunning, isTrue);
      await tester.pump();
      expect(f.nvml.reads, 2);
      f.nvml.complete(const [
        NvidiaGpuSample(index: 0, usage: 0.9, name: 'RTX'),
      ]);
      await tester.pump();
      expect(f.samples, hasLength(1));
      expect(f.samples.single.single.usage, closeTo(0.9, 1e-9));
      expect(f.samples.single.single.name, 'RTX');
      // The same NVML facade survives pause/resume; disposal happens once,
      // at sampler teardown.
      expect(f.nvml.reads, 2);
      expect(f.nvml.disposed, 0);
    },
  );

  testWidgets('a fast resume drops the stale read and starts a new one', (
    tester,
  ) async {
    final f = _blockingFixture();
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.nvml.reads, 1);

    f.sampler.pause();
    f.sampler.resume();
    await tester.pump();
    // The stale read is still in flight; resume queued a resample instead of
    // starting an overlapping read.
    expect(f.nvml.reads, 1);
    f.nvml.complete(_blockingSample);
    await tester.pump();
    expect(f.samples, isEmpty);
    expect(f.nvml.reads, 2);

    f.nvml.complete(const [NvidiaGpuSample(index: 0, usage: 0.7, name: 'RTX')]);
    await tester.pump();
    expect(f.samples, hasLength(1));
    expect(f.samples.single.single.usage, closeTo(0.7, 1e-9));
    expect(f.nvml.maxActive, 1);
  });

  testWidgets('a paused start does no work until resumed', (tester) async {
    final f = _blockingFixture();
    addTearDown(f.dispose);

    f.sampler.start(paused: true);
    expect(f.sampler.isRunning, isFalse);
    f.sampler.pause();
    await tester.pump();
    expect(f.samples, isEmpty);
    expect(f.nvml.reads, 0);

    f.sampler.resume();
    await tester.pump();
    expect(f.nvml.reads, 1);
    f.nvml.complete(_blockingSample);
    await tester.pump();
    expect(f.samples, hasLength(1));
  });

  testWidgets('resume before start is a no-op', (tester) async {
    final f = _blockingFixture();
    addTearDown(f.dispose);

    f.sampler.resume();
    await tester.pump();
    expect(f.sampler.isRunning, isFalse);
    expect(f.nvml.reads, 0);

    f.sampler.start();
    await tester.pump();
    expect(f.nvml.reads, 1);
  });

  testWidgets('a second start does not add a second timer', (tester) async {
    final f = _blockingFixture(interval: const Duration(milliseconds: 20));
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    f.nvml.complete(_blockingSample);
    await tester.pump();
    expect(f.samples, hasLength(1));

    f.sampler.start();
    await tester.pump(const Duration(milliseconds: 21));
    expect(f.nvml.reads, 2);
    f.nvml.complete(_blockingSample);
    await tester.pump();
    expect(f.samples, hasLength(2));
    expect(f.nvml.maxActive, 1);
  });

  testWidgets('dispose with a read in flight never adds after close', (
    tester,
  ) async {
    final f = _blockingFixture();
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    expect(f.nvml.reads, 1);

    await f.sampler.dispose();
    f.nvml.complete(_blockingSample);
    await tester.pump();
    expect(f.samples, isEmpty);
    expect(f.nvml.disposed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose while paused never revives the sampler', (tester) async {
    final f = _blockingFixture();
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    f.sampler.pause();
    await f.sampler.dispose();
    f.sampler.resume();
    await tester.pump();
    expect(f.sampler.isRunning, isFalse);
    expect(f.nvml.disposed, 1);
  });

  testWidgets('start after dispose stays terminal', (tester) async {
    final f = _blockingFixture(interval: const Duration(milliseconds: 10));
    addTearDown(f.dispose);

    await f.sampler.dispose();
    f.sampler.start();
    await tester.pump(const Duration(milliseconds: 11));
    expect(f.sampler.isRunning, isFalse);
    expect(f.nvml.reads, 0);
    expect(f.samples, isEmpty);
  });

  testWidgets('history and names survive a pause and resume', (tester) async {
    final f = _blockingFixture();
    addTearDown(f.dispose);

    f.sampler.start();
    await tester.pump();
    f.nvml.complete(_blockingSample);
    await tester.pump();

    f.sampler.pause();
    f.sampler.resume();
    await tester.pump();
    f.nvml.complete(const [NvidiaGpuSample(index: 0, usage: 0.6, name: 'RTX')]);
    await tester.pump();

    final load = f.samples.last.single;
    expect(load.name, 'RTX');
    expect(load.history, [0.4, 0.6]);
    expect(load.usage, closeTo(0.6, 1e-9));
  });

  test('gpu load json round-trips', () {
    final load = const GpuLoad(
      id: 'card0',
      label: 'AMD',
    ).append(0.4).append(0.7);
    final decoded = GpuLoad.fromJson(Map<String, dynamic>.from(load.toJson()));
    expect(decoded, load);
  });
}
