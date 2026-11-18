import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:trickster/src/bar/calendar.dart';
import 'package:trickster/src/bar/overlay_tooltip.dart';
import 'package:trickster/src/bar/tray_menu.dart';
import 'package:trickster/src/bar/volume_slider.dart';
import 'package:trickster/src/state/calendar_bloc.dart';
import 'package:trickster/src/state/overlay_tooltip.dart';
import 'package:trickster/src/state/tray_menu.dart';
import 'package:trickster/src/state/volume_slider_bloc.dart';

/// The slice of an overlay state that belongs to one view: whether the view
/// hosts this kind of overlay surface, and the session it hosts.
///
/// Records compare by value, so a selector returning one rebuilds its view
/// only when that view's own session or ownership changes — never when a
/// different view's overlay opens, moves, or closes.
typedef _ViewSession<T> = ({bool owns, T? session});

/// What one view paints: its own overlay session, or [strip] when it hosts no
/// overlay. Every selector is keyed by [viewId], so an overlay on another
/// output cannot rebuild this strip.
class OverlayViewSlot extends StatelessWidget {
  const OverlayViewSlot({
    required this.viewId,
    required this.strip,
    super.key,
  });

  /// The Flutter view whose overlays this slot paints.
  final int viewId;

  /// The strip painted when this view hosts no overlay surface.
  final WidgetBuilder strip;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      TrayMenuBloc,
      TrayMenuState,
      _ViewSession<TrayMenuSession>
    >(
      selector: (state) {
        final session = state.session;
        return (
          owns: state.isMenuView(viewId),
          session: session != null && session.viewId == viewId ? session : null,
        );
      },
      builder: (context, menu) => BlocSelector<
        CalendarBloc,
        CalendarState,
        _ViewSession<CalendarSession>
      >(
        selector: (state) {
          final session = state.session;
          return (
            owns: state.isCalendarView(viewId),
            session: session != null && session.viewId == viewId ? session : null,
          );
        },
        builder: (context, calendar) => BlocSelector<
          VolumeSliderBloc,
          VolumeSliderState,
          _ViewSession<VolumeSliderSession>
        >(
          selector: (state) {
            final session = state.session;
            return (
              owns: state.isSliderView(viewId),
              session:
                  session != null && session.viewId == viewId ? session : null,
            );
          },
          builder: (context, slider) => BlocSelector<
            OverlayTooltipBloc,
            OverlayTooltipState,
            _ViewSession<OverlayTooltipSession>
          >(
            selector: (state) {
              final session = state.session;
              return (
                owns: state.isTooltipView(viewId),
                session:
                    session != null && session.viewId == viewId ? session : null,
              );
            },
            builder: (context, tooltip) {
              if (menu.owns) {
                final session = menu.session;
                return session == null
                    ? const SizedBox.shrink()
                    : TrayMenuSurface(session: session);
              }
              if (calendar.owns) {
                final session = calendar.session;
                return session == null
                    ? const SizedBox.shrink()
                    : CalendarSurface(session: session);
              }
              if (slider.owns) {
                final session = slider.session;
                return session == null
                    ? const SizedBox.shrink()
                    : VolumeSliderSurface(session: session);
              }
              if (tooltip.owns) {
                final session = tooltip.session;
                return session == null
                    ? const SizedBox.shrink()
                    : OverlayTooltipSurface(session: session);
              }
              return strip(context);
            },
          ),
        ),
      ),
    );
  }
}
