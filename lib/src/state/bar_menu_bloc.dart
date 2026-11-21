import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/platform/settings_launcher.dart';
import 'package:trickster/src/services/overlay_coordinator.dart';
import 'package:trickster/src/theme/accent.dart';

/// The launcher the menu runs when its settings entry is selected. Injecting
/// it keeps widget and bloc tests from opening a real process.
typedef BarMenuSettingsLauncher = Future<bool> Function();

/// One open bar menu: where the empty strip was clicked and the overlay
/// surface hosting the panel.
@immutable
class BarMenuSession {
  const BarMenuSession({
    required this.viewId,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  /// The Flutter view of the overlay surface hosting this menu.
  final int viewId;
  final WallpaperAccent accent;

  /// Click position in the bar surface's coordinate space.
  final Offset click;
  final SystemBarSide side;
  final double thickness;
}

sealed class BarMenuEvent extends Equatable {
  const BarMenuEvent();

  @override
  List<Object?> get props => [];
}

/// Opens the bar menu on the bar surface [barViewId]. A request that arrives
/// while the menu is already open is ignored: a fullscreen overlay already
/// owns the pointer, and a repeated event must not create a second surface.
class BarMenuRequested extends BarMenuEvent {
  const BarMenuRequested({
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

class BarMenuDismissed extends BarMenuEvent {
  const BarMenuDismissed({this.done});

  /// Completed after the native surface is closed when the coordinator asks
  /// for a dismissal; a short timeout bounds a dead surface.
  final Completer<void>? done;
}

/// The settings entry was chosen. The bloc closes the surface first, then
/// starts the settings process, so the menu can never outlive its selection.
class BarMenuSettingsSelected extends BarMenuEvent {
  const BarMenuSettingsSelected();
}

/// Drops remembered surfaces that no longer exist on the engine.
class BarMenuViewsRetained extends BarMenuEvent {
  const BarMenuViewsRetained(this.viewIds);

  final Set<int> viewIds;

  @override
  List<Object?> get props => [...viewIds];
}

/// The bar menu overlay: the open session and the views it owns.
class BarMenuState extends Equatable {
  const BarMenuState({this.session, this.barMenuViewIds = const <int>{}});

  final BarMenuSession? session;

  /// Menu surfaces this process owns, open or closing; kept until the view is
  /// gone so the surface never renders a bar strip mid-teardown.
  final Set<int> barMenuViewIds;

  bool get isOpen => session != null;

  bool isBarMenuView(int viewId) => barMenuViewIds.contains(viewId);

  BarMenuState copyWith({Object? session = _unset, Set<int>? barMenuViewIds}) {
    return BarMenuState(
      session: identical(session, _unset)
          ? this.session
          : session as BarMenuSession?,
      barMenuViewIds: barMenuViewIds ?? this.barMenuViewIds,
    );
  }

  @override
  List<Object?> get props => [session, ...barMenuViewIds];

  Map<String, Object?> toJson() {
    final open = session;
    return {
      'bar_menu_views': barMenuViewIds.toList()..sort(),
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
  /// rebuilt; the open menu itself is runtime-only.
  static BarMenuState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('bar menu state must be an object');
    }
    final views = json['bar_menu_views'];
    return BarMenuState(
      barMenuViewIds: views is List
          ? {
              for (final view in views)
                if (view is num) view.toInt(),
            }
          : const <int>{},
    );
  }
}

const _unset = Object();

/// Owns the empty-strip context menu lifecycle: it opens a fullscreen overlay
/// surface on the bar's output, hands the session to the menu view, and
/// destroys the surface on dismissal. The bar's own surface never changes
/// size, so an open menu cannot stretch the strip.
class BarMenuBloc extends Bloc<BarMenuEvent, BarMenuState> {
  BarMenuBloc({
    required LayerShell layerShell,
    OverlayCoordinator? coordinator,
    BarMenuSettingsLauncher? launchSettings,
    String? configPath,
  }) : _layerShell = layerShell,
       _coordinator = coordinator,
       _launchSettings =
           launchSettings ??
           (() => launchTricksterSettings(configPath: configPath)),
       super(const BarMenuState()) {
    on<BarMenuRequested>(_onRequested);
    on<BarMenuDismissed>(_onDismissed);
    on<BarMenuSettingsSelected>(_onSettingsSelected);
    on<BarMenuViewsRetained>((event, emit) {
      final session = state.session;
      final retained =
          session != null && event.viewIds.contains(session.viewId);
      if (session != null && !retained) {
        _coordinator?.release(OverlayKind.barMenu);
      }
      emit(
        state.copyWith(
          session: retained ? session : null,
          barMenuViewIds: state.barMenuViewIds
              .where((viewId) => event.viewIds.contains(viewId))
              .toSet(),
        ),
      );
    });
    _coordinator?.register(OverlayKind.barMenu, _dismissFromCoordinator);
  }

  final LayerShell _layerShell;
  final OverlayCoordinator? _coordinator;
  final BarMenuSettingsLauncher _launchSettings;

  var _generation = 0;

  Future<void> _onRequested(
    BarMenuRequested event,
    Emitter<BarMenuState> emit,
  ) async {
    // One surface per open menu: a duplicate right-click must not flash a
    // second overlay or leak its native view.
    if (state.session != null) {
      return;
    }
    final coordinator = _coordinator;
    if (coordinator != null &&
        !await coordinator.request(OverlayKind.barMenu)) {
      return;
    }
    final generation = ++_generation;
    int? viewId;
    try {
      viewId = await _layerShell.openMenuSurface(
        barViewId: event.barViewId,
        side: event.side.name,
      );
    } on Object {
      // A missing native surface is a dismissal, never a crash.
      viewId = null;
    }
    if (viewId == null || generation != _generation) {
      if (viewId != null) {
        await _layerShell.closeMenuSurface(viewId: viewId);
      }
      if (generation == _generation) {
        coordinator?.release(OverlayKind.barMenu);
      }
      return;
    }
    emit(
      state.copyWith(
        session: BarMenuSession(
          viewId: viewId,
          accent: event.accent,
          click: event.click,
          side: event.side,
          thickness: event.thickness,
        ),
        barMenuViewIds: {...state.barMenuViewIds, viewId},
      ),
    );
    await _layerShell.showMenuSurface(viewId: viewId);
  }

  Future<void> _onDismissed(
    BarMenuDismissed event,
    Emitter<BarMenuState> emit,
  ) async {
    final session = state.session;
    emit(state.copyWith(session: null));
    _generation += 1;
    _coordinator?.release(OverlayKind.barMenu);
    try {
      if (session != null) {
        await _layerShell.closeMenuSurface(viewId: session.viewId);
      }
    } on Object {
      // A surface already destroyed by output removal must not surface an
      // error from a user dismissal.
    } finally {
      event.done?.complete();
    }
  }

  /// Dismisses before launching so the selected item cannot be clicked twice
  /// and the settings window never opens behind a leftover overlay.
  Future<void> _onSettingsSelected(
    BarMenuSettingsSelected event,
    Emitter<BarMenuState> emit,
  ) async {
    final session = state.session;
    if (session == null) {
      return;
    }
    emit(state.copyWith(session: null));
    _generation += 1;
    _coordinator?.release(OverlayKind.barMenu);
    try {
      await _layerShell.closeMenuSurface(viewId: session.viewId);
    } on Object {
      // A surface already destroyed by output removal must not stop the
      // launch; the menu is dismissed either way.
    }
    await _launchSettings();
  }

  /// The coordinator's generation-safe dismissal: invalidate any in-flight
  /// open, then close the live surface through the normal event path.
  Future<void> _dismissFromCoordinator() async {
    if (isClosed) {
      return;
    }
    _generation += 1;
    final done = Completer<void>();
    try {
      add(BarMenuDismissed(done: done));
    } on StateError {
      return;
    }
    await done.future;
  }

  @override
  Future<void> close() async {
    _generation += 1;
    _coordinator?.release(OverlayKind.barMenu);
    _coordinator?.unregister(OverlayKind.barMenu);
    final viewId = state.session?.viewId;
    if (viewId != null) {
      try {
        await _layerShell.closeMenuSurface(viewId: viewId);
      } on Object {
        // The native surface can already be gone after output removal or
        // engine shutdown; teardown must still finish.
      }
    }
    return super.close();
  }
}
