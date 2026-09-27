import 'dart:async';
import 'dart:io' show stderr;
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/config/settings.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class SettingsLoaded extends SettingsEvent {
  const SettingsLoaded(this.settings);

  final BarSettings settings;

  @override
  List<Object?> get props => [settings];
}

class SettingsModulesChanged extends SettingsEvent {
  const SettingsModulesChanged(this.modules);

  final List<String> modules;

  @override
  List<Object?> get props => [...modules];
}

class SettingsAccentChanged extends SettingsEvent {
  const SettingsAccentChanged(this.accent);

  final Color? accent;

  @override
  List<Object?> get props => [accent];
}

/// A bar-side edit (the media pill's mode cycle); unlike [SettingsLoaded] it
/// is persisted, so the document and the settings application follow it.
class SettingsMediaModeChanged extends SettingsEvent {
  const SettingsMediaModeChanged(this.mode);

  final MediaMode mode;

  @override
  List<Object?> get props => [mode];
}

class SettingsBloc extends Bloc<SettingsEvent, BarSettings> {
  SettingsBloc([
    super.initialState = const BarSettings(),
    Future<void> Function(BarSettings settings)? onPersist,
  ]) : _onPersist = onPersist {
    on<SettingsLoaded>((event, emit) => emit(event.settings));
    on<SettingsModulesChanged>(
      (event, emit) => emit(state.copyWith(modules: event.modules)),
    );
    on<SettingsAccentChanged>(
      (event, emit) => emit(state.copyWith(accent: event.accent)),
    );
    on<SettingsMediaModeChanged>((event, emit) {
      final next = state.copyWith(
        media: state.media.copyWith(mode: event.mode),
      );
      emit(next);
      unawaited(_persist(next));
    });
  }

  /// Writes the document after a bar-side edit; null in tests and in
  /// processes that only read settings.
  final Future<void> Function(BarSettings settings)? _onPersist;

  Future<void> _persist(BarSettings settings) async {
    final persist = _onPersist;
    if (persist == null) {
      return;
    }
    try {
      await persist(settings);
    } on Object catch (error) {
      stderr.writeln('trickster: could not save the media mode: $error');
    }
  }
}
