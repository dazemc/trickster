import 'dart:async';

import 'package:bloc/bloc.dart';

sealed class ClockEvent {
  const ClockEvent();
}

class ClockTicked extends ClockEvent {
  const ClockTicked(this.now);

  final DateTime now;
}

class ClockState {
  const ClockState(this.now);

  final DateTime now;

  Map<String, Object?> toJson() => {
    'now': now.millisecondsSinceEpoch,
  };

  static ClockState fromJson(Map<String, dynamic> json) => ClockState(
    DateTime.fromMillisecondsSinceEpoch((json['now'] as num?)?.toInt() ?? 0),
  );
}

class ClockBloc extends Bloc<ClockEvent, ClockState> {
  ClockBloc({DateTime Function()? now, Duration? tick})
    : _now = now ?? DateTime.now,
      super(ClockState((now ?? DateTime.now)())) {
    on<ClockTicked>((event, emit) => emit(ClockState(event.now)));
    if (tick != null) {
      _timer = Timer.periodic(tick, (_) => add(ClockTicked(_now())));
    } else {
      _schedule();
    }
  }

  final DateTime Function() _now;
  Timer? _timer;

  void _schedule() {
    final now = _now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(next.difference(now), () {
      add(ClockTicked(_now()));
      _schedule();
    });
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    return super.close();
  }
}
