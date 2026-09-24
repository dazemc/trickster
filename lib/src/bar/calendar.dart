import 'dart:math' as math;

import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/state/calendar_bloc.dart';
import 'package:trickster/src/state/capabilities_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/tokens.dart';

/// The contents of one calendar surface: a fullscreen transparent overlay
/// with the month panel anchored at the strip's inner edge. Tapping the
/// empty area or pressing Escape dismisses it.
class CalendarSurface extends StatefulWidget {
  const CalendarSurface({required this.session, super.key});

  final CalendarSession session;

  @override
  State<CalendarSurface> createState() => _CalendarSurfaceState();
}

class _CalendarSurfaceState extends State<CalendarSurface> {
  static const double _cell = 34;
  static const int _weeks = 6;

  final FocusNode _focusNode = FocusNode(debugLabel: 'calendar');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _dismiss() =>
      context.read<CalendarBloc>().add(const CalendarDismissed());

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The strip's inner edge at the click's cross position, in output
  /// coordinates; mirrors the tray menu's anchor.
  Offset _anchor(Size size) {
    final session = widget.session;
    return switch (session.side) {
      SystemBarSide.top => Offset(session.click.dx, session.thickness),
      SystemBarSide.bottom => Offset(
        session.click.dx,
        size.height - session.thickness,
      ),
      SystemBarSide.left => Offset(session.thickness, session.click.dy),
      SystemBarSide.right => Offset(
        size.width - session.thickness,
        session.click.dy,
      ),
      SystemBarSide.hidden => session.click,
    };
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final size = MediaQuery.sizeOf(context);
    final anchor = _anchor(size);
    return Stack(
      fit: StackFit.expand,
      children: [
        // The empty area is the dismissal target; the panel below absorbs
        // its own taps.
        GestureDetector(behavior: HitTestBehavior.opaque, onTap: _dismiss),
        CustomSingleChildLayout(
          delegate: _CalendarLayoutDelegate(anchor: anchor, side: session.side),
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _handleKeyEvent,
            child: GestureDetector(
              onTap: () {},
              child: _CalendarPanel(
                key: const ValueKey<String>('calendar-panel'),
                month: session.month,
                accent: session.accent,
                onPrevious: () => context.read<CalendarBloc>().add(
                  const CalendarMonthShifted(-1),
                ),
                onNext: () => context.read<CalendarBloc>().add(
                  const CalendarMonthShifted(1),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Positions the measured calendar panel against the strip's inner edge,
/// centered on the click and clamped inside the output so a pill near a
/// corner never pushes it off screen.
class _CalendarLayoutDelegate extends SingleChildLayoutDelegate {
  const _CalendarLayoutDelegate({required this.anchor, required this.side});

  final Offset anchor;
  final SystemBarSide side;
  static const double margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = math.max(margin, size.width - childSize.width - margin);
    final maxY = math.max(margin, size.height - childSize.height - margin);
    return switch (side) {
      SystemBarSide.top || SystemBarSide.hidden => Offset(
        (anchor.dx - childSize.width / 2).clamp(margin, maxX),
        (anchor.dy + margin).clamp(margin, maxY),
      ),
      SystemBarSide.bottom => Offset(
        (anchor.dx - childSize.width / 2).clamp(margin, maxX),
        (anchor.dy - childSize.height - margin).clamp(margin, maxY),
      ),
      SystemBarSide.left => Offset(
        (anchor.dx + margin).clamp(margin, maxX),
        (anchor.dy - childSize.height / 2).clamp(margin, maxY),
      ),
      SystemBarSide.right => Offset(
        (anchor.dx - childSize.width - margin).clamp(margin, maxX),
        (anchor.dy - childSize.height / 2).clamp(margin, maxY),
      ),
    };
  }

  @override
  bool shouldRelayout(_CalendarLayoutDelegate oldDelegate) {
    return oldDelegate.anchor != anchor || oldDelegate.side != side;
  }
}

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.month,
    required this.accent,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final DateTime month;
  final WallpaperAccent accent;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    // Same transparency as the pills: the hosted-blur option turns both into
    // translucent glass, and without it both keep the opaque accent fill.
    final glass =
        context.select((CapabilitiesBloc bloc) => bloc.state.blur) &&
        context.select((SettingsBloc bloc) => bloc.state.appearance.blur);
    final first = DateTime(month.year, month.month);
    // Monday-first grid; the leading days come from the previous month.
    final lead = first.weekday - 1;
    final start = first.subtract(Duration(days: lead));
    final today = DateTime.now();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: glass ? null : accent.cardFill(),
        gradient: glass
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ShellMediaColors.darkness.withValues(alpha: 0.30),
                  ShellMediaColors.darkness.withValues(alpha: 0.26),
                ],
              )
            : null,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: ShellMediaColors.glassSurface),
        boxShadow: const [
          BoxShadow(color: Color(0x88000000), blurRadius: 18, spreadRadius: 1),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SizedBox(
          width: 7 * _CalendarSurfaceState._cell,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _CalendarArrow(
                    key: const ValueKey<String>('calendar-prev'),
                    label: l10n.calendarPreviousMonth,
                    glyph: LucideIcons.chevronLeft,
                    onPressed: onPrevious,
                  ),
                  Expanded(
                    child: Text(
                      DateFormat.yMMMM(locale).format(first),
                      textAlign: TextAlign.center,
                      style: ShellText.systemBarValue,
                    ),
                  ),
                  _CalendarArrow(
                    key: const ValueKey<String>('calendar-next'),
                    label: l10n.calendarNextMonth,
                    glyph: LucideIcons.chevronRight,
                    onPressed: onNext,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var day = 0; day < 7; day++)
                    SizedBox(
                      width: _CalendarSurfaceState._cell,
                      child: Text(
                        DateFormat.E(
                          locale,
                        ).format(start.add(Duration(days: day))),
                        textAlign: TextAlign.center,
                        style: ShellText.systemBarCaption.copyWith(
                          color: ShellMediaColors.lightForegroundSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var week = 0; week < _CalendarSurfaceState._weeks; week++)
                Row(
                  children: [
                    for (var day = 0; day < 7; day++)
                      _CalendarDay(
                        date: start.add(Duration(days: week * 7 + day)),
                        month: first.month,
                        today: today,
                        accent: accent,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.month,
    required this.today,
    required this.accent,
  });

  final DateTime date;
  final int month;
  final DateTime today;
  final WallpaperAccent accent;

  @override
  Widget build(BuildContext context) {
    final inMonth = date.month == month;
    final isToday =
        date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Semantics(
      label: DateFormat.yMMMMd(locale).format(date),
      child: SizedBox(
        width: _CalendarSurfaceState._cell,
        height: _CalendarSurfaceState._cell,
        child: Center(
          child: DecoratedBox(
            key: ValueKey<String>(
              'calendar-day-${date.year}-'
              '${date.month.toString().padLeft(2, '0')}-'
              '${date.day.toString().padLeft(2, '0')}',
            ),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isToday ? accent.color : null,
            ),
            child: SizedBox.square(
              dimension: 26,
              child: Center(
                child: Text(
                  '${date.day}',
                  style: ShellText.systemBarCaption.copyWith(
                    color: isToday
                        ? ShellMediaColors.darkness
                        : inMonth
                        ? ShellMediaColors.lightForeground
                        : ShellMediaColors.lightForegroundSecondary.withValues(
                            alpha: 0.4,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarArrow extends StatelessWidget {
  const _CalendarArrow({
    required this.label,
    required this.glyph,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData glyph;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 26,
              child: Center(
                child: Icon(
                  glyph,
                  size: 16,
                  color: ShellMediaColors.lightForeground,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
