import 'dart:async';

import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/settings/bloc.dart';

/// Applies a settings change to the bloc immediately (live preview) and saves
/// it after a short quiet period, so dragging a control or reordering several
/// modules writes the document once.
class DebouncedSaver {
  DebouncedSaver(this.bloc, {this.delay = const Duration(milliseconds: 300)});

  final SettingsAppBloc bloc;
  final Duration delay;

  Timer? _timer;

  /// [change] receives the current settings and returns the next ones.
  void apply(BarSettings Function(BarSettings) change) {
    final next = change(bloc.settings);
    bloc.add(SettingsAppPreviewed(next));
    _timer?.cancel();
    _timer = Timer(delay, () => bloc.add(SettingsAppSaveRequested(next)));
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
