import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/services/status_notifier.dart';
import 'package:trickster/src/theme/accent.dart';

/// One open tray menu: the entries to render, where the strip was clicked,
/// and the overlay surface hosting the panel.
@immutable
class TrayMenuSession {
  const TrayMenuSession({
    required this.viewId,
    required this.item,
    required this.entries,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  /// The Flutter view of the overlay surface hosting this menu.
  final int viewId;
  final SystemTrayItem item;
  final List<SystemTrayMenuEntry> entries;
  final WallpaperAccent accent;

  /// Click position in the bar surface's coordinate space.
  final Offset click;
  final SystemBarSide side;
  final double thickness;
}

sealed class TrayMenuEvent extends Equatable {
  const TrayMenuEvent();

  @override
  List<Object?> get props => [];
}

/// Opens [entries] for [item] on the bar surface [barViewId], replacing any
/// menu already open.
class TrayMenuRequested extends TrayMenuEvent {
  const TrayMenuRequested({
    required this.barViewId,
    required this.item,
    required this.entries,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  final int barViewId;
  final SystemTrayItem item;
  final List<SystemTrayMenuEntry> entries;
  final WallpaperAccent accent;
  final Offset click;
  final SystemBarSide side;
  final double thickness;

  @override
  List<Object?> get props => [
    barViewId,
    item,
    ...entries,
    accent,
    click,
    side,
    thickness,
  ];
}

class TrayMenuDismissed extends TrayMenuEvent {
  const TrayMenuDismissed();
}

/// Drops remembered surfaces that no longer exist on the engine.
class TrayMenuViewsRetained extends TrayMenuEvent {
  const TrayMenuViewsRetained(this.viewIds);

  final Set<int> viewIds;

  @override
  List<Object?> get props => [...viewIds];
}

/// The tray menu overlay: the open session and the views it owns.
class TrayMenuState extends Equatable {
  const TrayMenuState({this.session, this.menuViewIds = const <int>{}});

  final TrayMenuSession? session;

  /// Menu surfaces this process owns, open or closing; kept until the view
  /// is gone so the surface never renders a bar strip mid-teardown.
  final Set<int> menuViewIds;

  bool get isOpen => session != null;

  bool isMenuView(int viewId) => menuViewIds.contains(viewId);

  TrayMenuState copyWith({Object? session = _unset, Set<int>? menuViewIds}) {
    return TrayMenuState(
      session: identical(session, _unset)
          ? this.session
          : session as TrayMenuSession?,
      menuViewIds: menuViewIds ?? this.menuViewIds,
    );
  }

  @override
  List<Object?> get props => [session, ...menuViewIds];

  Map<String, Object?> toJson() {
    final open = session;
    return {
      'menu_views': menuViewIds.toList()..sort(),
      if (open != null)
        'open': {
          'view_id': open.viewId,
          'item': open.item.toJson(),
          'entries': [for (final entry in open.entries) entry.label],
          'click': {'dx': open.click.dx, 'dy': open.click.dy},
          'side': open.side.name,
          'thickness': open.thickness,
        },
    };
  }

  /// A session names a live engine view and D-Bus item, so only the view
  /// bookkeeping is rebuilt; the open menu itself is runtime-only.
  static TrayMenuState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('tray menu state must be an object');
    }
    final views = json['menu_views'];
    return TrayMenuState(
      menuViewIds: views is List
          ? {
              for (final view in views)
                if (view is num) view.toInt(),
            }
          : const <int>{},
    );
  }
}

const _unset = Object();

/// Owns the menu lifecycle: it opens a fullscreen overlay surface on the
/// bar's output, hands the session to the menu view, and destroys the
/// surface on dismissal. The bar's own surface never changes size, so an
/// open menu cannot stretch the strip.
class TrayMenuBloc extends Bloc<TrayMenuEvent, TrayMenuState> {
  TrayMenuBloc({
    required LayerShell layerShell,
    void Function(SystemTrayItem item, Offset position)? onUnavailable,
  }) : _layerShell = layerShell,
       _onUnavailable = onUnavailable,
       super(const TrayMenuState()) {
    on<TrayMenuRequested>(_onRequested);
    on<TrayMenuDismissed>(_onDismissed);
    on<TrayMenuViewsRetained>((event, emit) {
      emit(
        state.copyWith(
          menuViewIds: state.menuViewIds
              .where((viewId) => event.viewIds.contains(viewId))
              .toSet(),
        ),
      );
    });
  }

  final LayerShell _layerShell;

  /// Called when the overlay surface could not be created, so the item can
  /// fall back to its own D-Bus context menu.
  final void Function(SystemTrayItem item, Offset position)? _onUnavailable;

  var _generation = 0;

  Future<void> _onRequested(
    TrayMenuRequested event,
    Emitter<TrayMenuState> emit,
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
      _onUnavailable?.call(event.item, event.click);
      return;
    }
    emit(
      state.copyWith(
        session: TrayMenuSession(
          viewId: viewId,
          item: event.item,
          entries: event.entries,
          accent: event.accent,
          click: event.click,
          side: event.side,
          thickness: event.thickness,
        ),
        menuViewIds: {...state.menuViewIds, viewId},
      ),
    );
    await _layerShell.showMenuSurface(viewId: viewId);
  }

  Future<void> _onDismissed(
    TrayMenuDismissed event,
    Emitter<TrayMenuState> emit,
  ) async {
    final session = state.session;
    emit(state.copyWith(session: null));
    _generation += 1;
    if (session != null) {
      await _layerShell.closeMenuSurface(viewId: session.viewId);
    }
  }
}
