import 'dart:async';
import 'dart:io';
import 'dart:ui' show Offset;

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/services/status_notifier.dart';

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
  }

  final StatusNotifierService _service;
  final void Function(String message) _log;
  StreamSubscription<List<SystemTrayItem>>? _subscription;

  /// Invokes an item method with the pointer position; false when the item
  /// refused every interface.
  Future<bool> invoke(
    SystemTrayItem item,
    SystemTrayAction action,
    Offset position,
  ) async {
    final invoked = await _service.invoke(item, action, position);
    if (!invoked) {
      _log('trickster: could not ${action.name} tray item ${item.id}');
    }
    return invoked;
  }

  /// Reads the item's D-Bus menu layout, or null when it has none.
  Future<List<SystemTrayMenuEntry>?> loadMenu(SystemTrayItem item) =>
      _service.loadMenu(item);

  /// Sends a menu entry click for [item] through to the item's bus owner.
  Future<bool> activateMenuEntry(SystemTrayItem item, int entryId) =>
      _service.activateMenuEntry(item, entryId);

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

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _service.dispose();
    return super.close();
  }
}

void _stderrLog(String message) => stderr.writeln(message);
