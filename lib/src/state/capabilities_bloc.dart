import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import 'package:trickster/src/platform/layer_shell.dart';

/// Host capabilities, probed at startup and updated when the compositor
/// changes them.
class Capabilities extends Equatable {
  const Capabilities({this.blur = false});

  /// Whether the compositor advertises blur through
  /// `ext-background-effect-v1`.
  final bool blur;

  Capabilities copyWith({bool? blur}) =>
      Capabilities(blur: blur ?? this.blur);

  Map<String, Object?> toJson() => {'blur': blur};

  static Capabilities fromJson(Map<String, dynamic> json) =>
      Capabilities(blur: json['blur'] as bool? ?? false);

  @override
  List<Object?> get props => [blur];
}

sealed class CapabilitiesEvent extends Equatable {
  const CapabilitiesEvent();

  @override
  List<Object?> get props => [];
}

class CapabilitiesProbeRequested extends CapabilitiesEvent {
  const CapabilitiesProbeRequested();
}

class CapabilitiesBlurChanged extends CapabilitiesEvent {
  const CapabilitiesBlurChanged(this.blur);

  final bool blur;

  @override
  List<Object?> get props => [blur];
}

class CapabilitiesBloc extends Bloc<CapabilitiesEvent, Capabilities> {
  CapabilitiesBloc({
    Future<bool> Function()? probe,
    Stream<bool> Function()? changes,
    Capabilities? initial,
  }) : _probe = probe ?? _nativeProbe,
       super(initial ?? const Capabilities()) {
    on<CapabilitiesProbeRequested>(_onProbeRequested);
    on<CapabilitiesBlurChanged>(_onBlurChanged);
    _subscription = (changes ?? _nativeChanges)().listen(
      (blur) => add(CapabilitiesBlurChanged(blur)),
    );
  }

  final Future<bool> Function() _probe;
  StreamSubscription<bool>? _subscription;

  static Future<bool> _nativeProbe() => LayerShell().blurSupported();
  static Stream<bool> _nativeChanges() => LayerShell.blurChanges;

  Future<void> _onProbeRequested(
    CapabilitiesProbeRequested event,
    Emitter<Capabilities> emit,
  ) async {
    bool blur;
    try {
      blur = await _probe();
    } on Object {
      blur = false;
    }
    emit(Capabilities(blur: blur));
  }

  void _onBlurChanged(
    CapabilitiesBlurChanged event,
    Emitter<Capabilities> emit,
  ) {
    emit(state.copyWith(blur: event.blur));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
