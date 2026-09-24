import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/platform/layer_shell.dart';
import 'package:trickster/src/theme/accent.dart';

/// One open calendar: the month it shows, where the clock was clicked, and
/// the overlay surface hosting it.
@immutable
class CalendarSession {
  const CalendarSession({
    required this.viewId,
    required this.month,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  /// The Flutter view of the overlay surface hosting this calendar.
  final int viewId;

  /// The first of the month on display.
  final DateTime month;
  final WallpaperAccent accent;

  /// Click position in the bar surface's coordinate space.
  final Offset click;
  final SystemBarSide side;
  final double thickness;
}

sealed class CalendarEvent extends Equatable {
  const CalendarEvent();

  @override
  List<Object?> get props => [];
}

/// Opens a calendar for [month] on the bar surface [barViewId], replacing any
/// calendar already open.
class CalendarRequested extends CalendarEvent {
  const CalendarRequested({
    required this.barViewId,
    required this.month,
    required this.accent,
    required this.click,
    required this.side,
    required this.thickness,
  });

  final int barViewId;
  final DateTime month;
  final WallpaperAccent accent;
  final Offset click;
  final SystemBarSide side;
  final double thickness;

  @override
  List<Object?> get props => [barViewId, month, accent, click, side, thickness];
}

class CalendarDismissed extends CalendarEvent {
  const CalendarDismissed();
}

/// Moves the open calendar by [months], relative to the month on display, so
/// rapid clicks never race a stale widget build.
class CalendarMonthShifted extends CalendarEvent {
  const CalendarMonthShifted(this.months);

  final int months;

  @override
  List<Object?> get props => [months];
}

/// Drops remembered surfaces that no longer exist on the engine.
class CalendarViewsRetained extends CalendarEvent {
  const CalendarViewsRetained(this.viewIds);

  final Set<int> viewIds;

  @override
  List<Object?> get props => [...viewIds];
}

/// The calendar overlay: the open session and the views it owns.
class CalendarState extends Equatable {
  const CalendarState({this.session, this.calendarViewIds = const <int>{}});

  final CalendarSession? session;

  /// Calendar surfaces this process owns, open or closing; kept until the
  /// view is gone so the surface never renders a bar strip mid-teardown.
  final Set<int> calendarViewIds;

  bool get isOpen => session != null;

  bool isCalendarView(int viewId) => calendarViewIds.contains(viewId);

  CalendarState copyWith({
    Object? session = _unset,
    Set<int>? calendarViewIds,
  }) {
    return CalendarState(
      session: identical(session, _unset)
          ? this.session
          : session as CalendarSession?,
      calendarViewIds: calendarViewIds ?? this.calendarViewIds,
    );
  }

  @override
  List<Object?> get props => [session, ...calendarViewIds];

  Map<String, Object?> toJson() {
    final open = session;
    return {
      'calendar_views': calendarViewIds.toList()..sort(),
      if (open != null)
        'open': {
          'view_id': open.viewId,
          'month': open.month.millisecondsSinceEpoch,
          'click': {'dx': open.click.dx, 'dy': open.click.dy},
          'side': open.side.name,
          'thickness': open.thickness,
        },
    };
  }

  /// A session names a live engine view, so only the view bookkeeping is
  /// rebuilt; the open calendar itself is runtime-only.
  static CalendarState fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('calendar state must be an object');
    }
    final views = json['calendar_views'];
    return CalendarState(
      calendarViewIds: views is List
          ? {
              for (final view in views)
                if (view is num) view.toInt(),
            }
          : const <int>{},
    );
  }
}

const _unset = Object();

/// Owns the calendar lifecycle: it opens a fullscreen overlay surface on the
/// bar's output, hands the session to the calendar view, and destroys the
/// surface on dismissal. The bar's own surface never changes size.
class CalendarBloc extends Bloc<CalendarEvent, CalendarState> {
  CalendarBloc({required LayerShell layerShell})
    : _layerShell = layerShell,
      super(const CalendarState()) {
    on<CalendarRequested>(_onRequested);
    on<CalendarDismissed>(_onDismissed);
    on<CalendarMonthShifted>((event, emit) {
      final session = state.session;
      if (session == null) {
        return;
      }
      emit(
        state.copyWith(
          session: CalendarSession(
            viewId: session.viewId,
            month: DateTime(
              session.month.year,
              session.month.month + event.months,
            ),
            accent: session.accent,
            click: session.click,
            side: session.side,
            thickness: session.thickness,
          ),
        ),
      );
    });
    on<CalendarViewsRetained>((event, emit) {
      emit(
        state.copyWith(
          calendarViewIds: state.calendarViewIds
              .where((viewId) => event.viewIds.contains(viewId))
              .toSet(),
        ),
      );
    });
  }

  final LayerShell _layerShell;
  var _generation = 0;

  Future<void> _onRequested(
    CalendarRequested event,
    Emitter<CalendarState> emit,
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
        session: CalendarSession(
          viewId: viewId,
          month: DateTime(event.month.year, event.month.month),
          accent: event.accent,
          click: event.click,
          side: event.side,
          thickness: event.thickness,
        ),
        calendarViewIds: {...state.calendarViewIds, viewId},
      ),
    );
    await _layerShell.showMenuSurface(viewId: viewId);
  }

  Future<void> _onDismissed(
    CalendarDismissed event,
    Emitter<CalendarState> emit,
  ) async {
    final session = state.session;
    emit(state.copyWith(session: null));
    _generation += 1;
    if (session != null) {
      await _layerShell.closeMenuSurface(viewId: session.viewId);
    }
  }
}
