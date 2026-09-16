import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

sealed class ClockEvent extends Equatable {
  const ClockEvent();

  @override
  List<Object?> get props => [];
}

class ClockTicked extends ClockEvent {
  const ClockTicked(this.now);

  final DateTime now;

  @override
  List<Object?> get props => [now];
}

/// Switches the clock's tick cadence: seconds visible ticks every second,
/// otherwise the timer sleeps until the next minute.
class ClockCadenceChanged extends ClockEvent {
  const ClockCadenceChanged({required this.seconds});

  final bool seconds;

  @override
  List<Object?> get props => [seconds];
}

class ClockState extends Equatable {
  const ClockState(this.now);

  final DateTime now;

  @override
  List<Object?> get props => [now];

  Map<String, Object?> toJson() => {'now': now.millisecondsSinceEpoch};

  static ClockState fromJson(Map<String, dynamic> json) => ClockState(
    DateTime.fromMillisecondsSinceEpoch((json['now'] as num?)?.toInt() ?? 0),
  );
}

class ClockBloc extends Bloc<ClockEvent, ClockState> {
  ClockBloc({DateTime Function()? now, Duration? tick})
    : _now = now ?? DateTime.now,
      super(ClockState((now ?? DateTime.now)())) {
    on<ClockTicked>((event, emit) => emit(ClockState(event.now)));
    on<ClockCadenceChanged>(_onCadenceChanged);
    if (tick != null) {
      _timer = Timer.periodic(tick, (_) => add(ClockTicked(_now())));
    } else {
      _schedule();
    }
  }

  final DateTime Function() _now;
  Timer? _timer;
  var _seconds = false;

  void _onCadenceChanged(ClockCadenceChanged event, Emitter<ClockState> emit) {
    if (event.seconds == _seconds) {
      return;
    }
    _seconds = event.seconds;
    _timer?.cancel();
    _timer = null;
    if (_seconds) {
      emit(ClockState(_now()));
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => add(ClockTicked(_now())),
      );
      return;
    }
    _schedule();
  }

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
