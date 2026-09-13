import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';

/// Verbose observer for debug/profile runs: every bloc birth and death,
/// every event, every transition with handler latency, every error.
///
/// The transcript is the agent runtime-proof instrument — verify behavior by
/// reading it, not pixels. Production stays silent: [installObserver] only
/// installs in debug/profile builds, and nothing else in the app logs through
/// this path.
class TricksterObserver extends BlocObserver {
  TricksterObserver({void Function(String line)? log})
    : _log = log ?? stderr.writeln;

  final void Function(String line) _log;

  /// Event receipt times, keyed by bloc. Entries are removed on the matching
  /// transition or on close, so the map never outgrows the live bloc set.
  final Map<BlocBase<dynamic>, DateTime> _eventStarted = {};

  String _name(BlocBase<dynamic> bloc) => bloc.runtimeType.toString();

  @override
  void onCreate(BlocBase<dynamic> bloc) {
    super.onCreate(bloc);
    _log('bloc+ ${_name(bloc)} initial=${bloc.state}');
  }

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    _eventStarted[bloc] = DateTime.now();
    _log('evt   ${_name(bloc)} ${event.runtimeType}');
  }

  @override
  void onTransition(
    Bloc<dynamic, dynamic> bloc,
    Transition<dynamic, dynamic> transition,
  ) {
    super.onTransition(bloc, transition);
    final started = _eventStarted.remove(bloc);
    final elapsed = started == null
        ? '?'
        : '${DateTime.now().difference(started).inMicroseconds}µs';
    _log(
      'trn   ${_name(bloc)} ${transition.event.runtimeType} '
      '${transition.currentState} → ${transition.nextState} [$elapsed]',
    );
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    _log('err   ${_name(bloc)} $error');
  }

  @override
  void onClose(BlocBase<dynamic> bloc) {
    super.onClose(bloc);
    _eventStarted.remove(bloc);
    _log('bloc- ${_name(bloc)}');
  }
}

/// Installs the verbose observer in debug/profile builds. Release keeps the
/// default silent observer, so production logs nothing extra.
void installObserver() {
  if (kDebugMode || kProfileMode) {
    Bloc.observer = TricksterObserver();
  }
}
