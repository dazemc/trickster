import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';

class BatteryStatus extends Equatable {
  const BatteryStatus({this.capacity, this.charging = false});

  final int? capacity;
  final bool charging;

  @override
  List<Object?> get props => [capacity, charging];

  Map<String, Object?> toJson() => {
    'capacity': capacity,
    'charging': charging,
  };

  static BatteryStatus fromJson(Map<String, dynamic> json) =>
      BatteryStatus(
        capacity: (json['capacity'] as num?)?.toInt(),
        charging: (json['charging'] as bool?) ?? false,
      );
}

class BatterySampler {
  BatterySampler({this.interval = const Duration(seconds: 5)});

  final Duration interval;
  Timer? _timer;
  final _controller = StreamController<BatteryStatus>.broadcast();

  Stream<BatteryStatus> get snapshots => _controller.stream;

  void start() {
    _sample();
    _timer = Timer.periodic(interval, (_) => _sample());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller.close();
  }

  void _sample() {
    final root = Directory('/sys/class/power_supply');
    if (!root.existsSync()) {
      _controller.add(const BatteryStatus());
      return;
    }
    for (final entity in root.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      final name = entity.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last;
      if (!name.startsWith('BAT')) {
        continue;
      }
      final capacityFile = File('${entity.path}/capacity');
      final statusFile = File('${entity.path}/status');
      if (!capacityFile.existsSync()) {
        continue;
      }
      final capacity = int.tryParse(capacityFile.readAsStringSync().trim());
      final status = statusFile.existsSync()
          ? statusFile.readAsStringSync().trim()
          : '';
      _controller.add(
        BatteryStatus(
          capacity: capacity,
          charging: status == 'Charging' || status == 'Full',
        ),
      );
      return;
    }
    _controller.add(const BatteryStatus());
  }
}
