import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../services/status_notifier.dart';

sealed class TrayEvent extends Equatable {
  const TrayEvent();

  @override
  List<Object?> get props => [];
}

class TrayStarted extends TrayEvent {
  const TrayStarted();
}

class TrayStopped extends TrayEvent {
  const TrayStopped();
}

class TraySampled extends TrayEvent {
  const TraySampled(this.items);

  final List<SystemTrayItem> items;

  @override
  List<Object?> get props => [...items];
}

class TrayItemActivated extends TrayEvent {
  const TrayItemActivated(this.item, this.position);

  final SystemTrayItem item;
  final Offset position;

  @override
  List<Object?> get props => [item, position];
}

class TrayBloc extends Bloc<TrayEvent, TrayState> {
  TrayBloc({
    StatusNotifierService? service,
    TrayState initial = const TrayState(),
    void Function(String message)? log,
  }) : _service = service ?? StatusNotifierService(),
       _log = log ?? _stderrLog,
       super(initial) {
    on<TrayStarted>(_onStarted);
    on<TrayStopped>(_onStopped);
    on<TraySampled>((event, emit) => emit(TrayState(event.items)));
    on<TrayItemActivated>(_onActivated);
  }

  final StatusNotifierService _service;
  final void Function(String message) _log;
  StreamSubscription<List<SystemTrayItem>>? _subscription;

  Future<void> _onStarted(TrayStarted event, Emitter<TrayState> emit) async {
    _subscription ??= _service.snapshots.listen(
      (items) => add(TraySampled(items)),
    );
    try {
      await _service.start();
    } on Object catch (error) {
      _log('trickster: tray unavailable: $error');
    }
  }

  Future<void> _onStopped(TrayStopped event, Emitter<TrayState> emit) async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onActivated(
    TrayItemActivated event,
    Emitter<TrayState> emit,
  ) async {
    final activated = await _service.invoke(
      event.item,
      SystemTrayAction.activate,
      event.position,
    );
    if (!activated) {
      _log('trickster: could not activate tray item ${event.item.id}');
    }
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _service.dispose();
    return super.close();
  }
}

void _stderrLog(String message) => stderr.writeln(message);
