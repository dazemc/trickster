import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/theme/accent.dart';

/// One open volume slider: where the readout was clicked and the overlay
/// surface hosting it.
@immutable
class VolumeSliderSession {
  const VolumeSliderSession({
    required this.viewId,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  /// The Flutter view of the overlay surface hosting this slider.
  final int viewId;
  final WallpaperAccent accent;

  /// Click position in the bar surface's coordinate space.
  final Offset click;
  final SystemBarSide side;
  final double thickness;
}

sealed class VolumeSliderEvent extends Equatable {
  const VolumeSliderEvent();

  @override
  List<Object?> get props => [];
}

/// Opens the slider on the bar surface [barViewId], replacing any slider
/// already open.
class VolumeSliderRequested extends VolumeSliderEvent {
  const VolumeSliderRequested({
    required this.barViewId,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  final int barViewId;
  final WallpaperAccent accent;
  final Offset click;
  final SystemBarSide side;
  final double thickness;

  @override
  List<Object?> get props => [barViewId, accent, click, side, thickness];
}

class VolumeSliderDismissed extends VolumeSliderEvent {
  const VolumeSliderDismissed();
}

/// Drops remembered surfaces that no longer exist on the engine.
class VolumeSliderViewsRetained extends VolumeSliderEvent {
  const VolumeSliderViewsRetained(this.viewIds);

  final Set<int> viewIds;

  @override
  List<Object?> get props => [...viewIds];
}

/// The volume slider overlay: the open session and the views it owns.
class VolumeSliderState extends Equatable {
  const VolumeSliderState({this.session, this.sliderViewIds = const <int>{}});

  final VolumeSliderSession? session;

  /// Slider surfaces this process owns, open or closing; kept until the view
  /// is gone so the surface never renders a bar strip mid-teardown.
  final Set<int> sliderViewIds;

  bool get isOpen => session != null;

  bool isSliderView(int viewId) => sliderViewIds.contains(viewId);

  VolumeSliderState copyWith({
    Object? session = _unset,
    Set<int>? sliderViewIds,
  }) {
    return VolumeSliderState(
      session: identical(session, _unset)
          ? this.session
          : session as VolumeSliderSession?,
      sliderViewIds: sliderViewIds ?? this.sliderViewIds,
    );
  }

  @override
  List<Object?> get props => [session, ...sliderViewIds];

  Map<String, Object?> toJson() {
    final open = session;
    return {
      'slider_views': sliderViewIds.toList()..sort(),
      if (open != null)
        'open': {
          'view_id': open.viewId,
          'click': {'dx': open.click.dx, 'dy': open.click.dy},
          'side': open.side.name,
          'thickness': open.thickness,
        },
    };
  }

  /// A session names a live engine view, so only the view bookkeeping is
  /// rebuilt; the open slider itself is runtime-only.
  static VolumeSliderState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('volume slider state must be an object');
    }
    final views = json['slider_views'];
    return VolumeSliderState(
      sliderViewIds: views is List
          ? {
              for (final view in views)
                if (view is num) view.toInt(),
            }
          : const <int>{},
    );
  }
}

const _unset = Object();

/// Owns the volume slider lifecycle: it opens a fullscreen overlay surface on
/// the bar's output, hands the session to the slider view, and destroys the
/// surface on dismissal. The bar's own surface never changes size.
class VolumeSliderBloc extends Bloc<VolumeSliderEvent, VolumeSliderState> {
  VolumeSliderBloc({required LayerShell layerShell})
    : _layerShell = layerShell,
      super(const VolumeSliderState()) {
    on<VolumeSliderRequested>(_onRequested);
    on<VolumeSliderDismissed>(_onDismissed);
    on<VolumeSliderViewsRetained>((event, emit) {
      emit(
        state.copyWith(
          sliderViewIds: state.sliderViewIds
              .where((viewId) => event.viewIds.contains(viewId))
              .toSet(),
        ),
      );
    });
  }

  final LayerShell _layerShell;
  var _generation = 0;

  Future<void> _onRequested(
    VolumeSliderRequested event,
    Emitter<VolumeSliderState> emit,
  ) async {
    final generation = ++_generation;
    final previous = state.session;
    if (previous != null) {
      emit(state.copyWith(session: null));
      await _layerShell.closeMenuSurface(viewId: previous.viewId);
    }
    final viewId = await _layerShell.openMenuSurface(
      barViewId: event.barViewId,
      side: event.side.name,
    );
    if (viewId == null || generation != _generation) {
      if (viewId != null) {
        await _layerShell.closeMenuSurface(viewId: viewId);
      }
      return;
    }
    emit(
      state.copyWith(
        session: VolumeSliderSession(
          viewId: viewId,
          accent: event.accent,
          click: event.click,
          side: event.side,
          thickness: event.thickness,
        ),
        sliderViewIds: {...state.sliderViewIds, viewId},
      ),
    );
    await _layerShell.showMenuSurface(viewId: viewId);
  }

  Future<void> _onDismissed(
    VolumeSliderDismissed event,
    Emitter<VolumeSliderState> emit,
  ) async {
    final session = state.session;
    emit(state.copyWith(session: null));
    _generation += 1;
    if (session != null) {
      await _layerShell.closeMenuSurface(viewId: session.viewId);
    }
  }
}
