import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/theme/accent.dart';

/// One visible tray tooltip: the label to paint, where the hovered item sat,
/// and the overlay surface hosting it.
@immutable
class OverlayTooltipSession {
  const OverlayTooltipSession({
    required this.viewId,
    required this.itemId,
    required this.label,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  /// The Flutter view of the overlay surface hosting this tooltip.
  final int viewId;
  final String itemId;
  final String label;
  final WallpaperAccent accent;

  /// Hovered item center in the bar surface's coordinate space.
  final Offset click;
  final SystemBarSide side;
  final double thickness;
}

sealed class OverlayTooltipEvent extends Equatable {
  const OverlayTooltipEvent();

  @override
  List<Object?> get props => [];
}

/// Shows [label] for [itemId] near the hovered item, replacing any tooltip
/// already visible.
class OverlayTooltipRequested extends OverlayTooltipEvent {
  const OverlayTooltipRequested({
    required this.barViewId,
    required this.itemId,
    required this.label,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  final int barViewId;
  final String itemId;
  final String label;
  final WallpaperAccent accent;
  final Offset click;
  final SystemBarSide side;
  final double thickness;

  @override
  List<Object?> get props => [
    barViewId,
    itemId,
    label,
    accent,
    click,
    side,
    thickness,
  ];
}

/// Dismisses the tooltip. When [itemId] names a different item the request
/// is ignored, so a stale exit cannot hide a newer tooltip.
class OverlayTooltipDismissed extends OverlayTooltipEvent {
  const OverlayTooltipDismissed({this.itemId});

  final String? itemId;

  @override
  List<Object?> get props => [itemId];
}

/// Drops remembered surfaces that no longer exist on the engine.
class OverlayTooltipViewsRetained extends OverlayTooltipEvent {
  const OverlayTooltipViewsRetained(this.viewIds);

  final Set<int> viewIds;

  @override
  List<Object?> get props => [...viewIds];
}

/// The tooltip overlay: the visible session and the views it owns.
class OverlayTooltipState extends Equatable {
  const OverlayTooltipState({
    this.session,
    this.tooltipViewIds = const <int>{},
  });

  final OverlayTooltipSession? session;

  /// Tooltip surfaces this process owns, open or closing; kept until the view
  /// is gone so the surface never renders a bar strip mid-teardown.
  final Set<int> tooltipViewIds;

  bool get isOpen => session != null;

  bool isTooltipView(int viewId) => tooltipViewIds.contains(viewId);

  OverlayTooltipState copyWith({
    Object? session = _unset,
    Set<int>? tooltipViewIds,
  }) {
    return OverlayTooltipState(
      session: identical(session, _unset)
          ? this.session
          : session as OverlayTooltipSession?,
      tooltipViewIds: tooltipViewIds ?? this.tooltipViewIds,
    );
  }

  @override
  List<Object?> get props => [session, ...tooltipViewIds];

  Map<String, Object?> toJson() {
    final open = session;
    return {
      'tooltip_views': tooltipViewIds.toList()..sort(),
      if (open != null)
        'open': {
          'view_id': open.viewId,
          'item_id': open.itemId,
          'label': open.label,
          'click': {'dx': open.click.dx, 'dy': open.click.dy},
          'side': open.side.name,
          'thickness': open.thickness,
        },
    };
  }

  /// A session names a live engine view, so only the view bookkeeping is
  /// rebuilt; the visible tooltip itself is runtime-only.
  static OverlayTooltipState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('overlay tooltip state must be an object');
    }
    final views = json['tooltip_views'];
    return OverlayTooltipState(
      tooltipViewIds: views is List
          ? {
              for (final view in views)
                if (view is num) view.toInt(),
            }
          : const <int>{},
    );
  }
}

const _unset = Object();

/// Owns the tooltip lifecycle: it opens a click-through overlay surface on
/// the bar's output, retargets it as hover moves between items, and destroys
/// it when the pointer leaves. The strip surface never changes size.
class OverlayTooltipBloc
    extends Bloc<OverlayTooltipEvent, OverlayTooltipState> {
  OverlayTooltipBloc({required LayerShell layerShell})
    : _layerShell = layerShell,
      super(const OverlayTooltipState()) {
    on<OverlayTooltipRequested>(_onRequested);
    on<OverlayTooltipDismissed>(_onDismissed);
    on<OverlayTooltipViewsRetained>((event, emit) {
      emit(
        state.copyWith(
          tooltipViewIds: state.tooltipViewIds
              .where((viewId) => event.viewIds.contains(viewId))
              .toSet(),
        ),
      );
    });
  }

  final LayerShell _layerShell;
  var _generation = 0;

  Future<void> _onRequested(
    OverlayTooltipRequested event,
    Emitter<OverlayTooltipState> emit,
  ) async {
    final existing = state.session;
    if (existing != null) {
      if (existing.itemId == event.itemId && existing.label == event.label) {
        return;
      }
      // A surface already open on the same edge is retargeted in place, so
      // moving between tray items never churns Wayland surfaces.
      if (existing.side == event.side) {
        emit(
          state.copyWith(
            session: OverlayTooltipSession(
              viewId: existing.viewId,
              itemId: event.itemId,
              label: event.label,
              accent: event.accent,
              click: event.click,
              side: event.side,
              thickness: event.thickness,
            ),
          ),
        );
        return;
      }
    }
    final generation = ++_generation;
    if (existing != null) {
      emit(state.copyWith(session: null));
      await _layerShell.closeTooltipSurface(viewId: existing.viewId);
    }
    final viewId = await _layerShell.openTooltipSurface(
      barViewId: event.barViewId,
      side: event.side.name,
    );
    if (viewId == null || generation != _generation) {
      if (viewId != null) {
        await _layerShell.closeTooltipSurface(viewId: viewId);
      }
      return;
    }
    emit(
      state.copyWith(
        session: OverlayTooltipSession(
          viewId: viewId,
          itemId: event.itemId,
          label: event.label,
          accent: event.accent,
          click: event.click,
          side: event.side,
          thickness: event.thickness,
        ),
        tooltipViewIds: {...state.tooltipViewIds, viewId},
      ),
    );
    await _layerShell.showTooltipSurface(viewId: viewId);
  }

  Future<void> _onDismissed(
    OverlayTooltipDismissed event,
    Emitter<OverlayTooltipState> emit,
  ) async {
    final session = state.session;
    if (session == null ||
        (event.itemId != null && session.itemId != event.itemId)) {
      return;
    }
    emit(state.copyWith(session: null));
    _generation += 1;
    await _layerShell.closeTooltipSurface(viewId: session.viewId);
  }
}
