import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/state/calendar_bloc.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/motion.dart';
import 'package:trickster/src/theme/tokens.dart';

class ClockPill extends StatefulWidget {
  const ClockPill({
    required this.accent,
    this.format = ClockFormat.locale,
    this.showDate = true,
    this.showSeconds = false,
    this.dateStyle = ClockDateStyle.short,
    this.vertical = false,
    super.key,
  });

  final WallpaperAccent accent;
  final ClockFormat format;

  /// Whether the date caption renders beside the time.
  final bool showDate;

  /// Whether seconds join the time; the clock then ticks every second.
  final bool showSeconds;

  /// How much of the date the caption shows.
  final ClockDateStyle dateStyle;

  /// Vertical strips drop the date caption and show only the time.
  final bool vertical;

  @override
  State<ClockPill> createState() => _ClockPillState();
}

class _ClockPillState extends State<ClockPill> {
  bool? _seconds;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncCadence();
  }

  @override
  void didUpdateWidget(covariant ClockPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCadence();
  }

  /// Matches the tick cadence to what the pill paints: per second while the
  /// seconds show, minute-aligned otherwise. Runs on settings rebuilds too.
  void _syncCadence() {
    final seconds = widget.showSeconds && !widget.vertical;
    if (_seconds == seconds) {
      return;
    }
    _seconds = seconds;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ClockBloc>().add(ClockCadenceChanged(seconds: seconds));
      }
    });
  }

  /// Opens the month calendar on a transient overlay, anchored at the pill.
  void _openCalendar() {
    final geometry = StripGeometry.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    context.read<CalendarBloc>().add(
      CalendarRequested(
        barViewId: View.of(context).viewId,
        month: DateTime.now(),
        accent: widget.accent,
        click: box == null
            ? Offset.zero
            : box.localToGlobal(box.size.center(Offset.zero)),
        side: geometry?.side ?? SystemBarSide.top,
        thickness: geometry?.thickness ?? 32,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openCalendar,
        child: SystemBarCard(
          accent: widget.accent,
          padding: EdgeInsets.symmetric(horizontal: widget.vertical ? 6 : 12),
          child: BlocBuilder<ClockBloc, ClockState>(
            builder: (context, state) => _ClockRow(
              accent: widget.accent,
              now: state.now,
              format: widget.format,
              showDate: widget.showDate,
              showSeconds: widget.showSeconds,
              dateStyle: widget.dateStyle,
              vertical: widget.vertical,
              onTap: _openCalendar,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClockRow extends StatelessWidget {
  const _ClockRow({
    required this.accent,
    required this.now,
    required this.format,
    required this.showDate,
    required this.showSeconds,
    required this.dateStyle,
    required this.vertical,
    required this.onTap,
  });

  final WallpaperAccent accent;
  final DateTime now;
  final ClockFormat format;
  final bool showDate;
  final bool showSeconds;
  final ClockDateStyle dateStyle;
  final bool vertical;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(context, now);
    final date = _formatDate(context, now);
    final withDate = showDate && !vertical;
    return PillTooltip(
      accent: accent,
      label: withDate ? '$date $time' : time,
      child: Semantics(
        button: true,
        label: context.l10n.clockTitle,
        value: withDate ? '$date, $time' : time,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (withDate) ...[
                Flexible(
                  child: Text(
                    date,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: ShellText.systemBarCaption.copyWith(
                      color: accent.captionColor(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              AnimatedSwitcher(
                duration: Motion.cardSettle,
                switchInCurve: Motion.standard,
                switchOutCurve: Motion.standard,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: Text(
                  time,
                  key: ValueKey<String>(time),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: ShellText.systemBarValue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime now) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final format = this.format;
    final showSeconds = this.showSeconds;
    // The locale default follows the locale's own hour cycle: 12h with day
    // period where the locale prefers it, 24h where it does not.
    return switch (format) {
      ClockFormat.locale =>
        showSeconds
            ? DateFormat.jms(locale).format(now)
            : DateFormat.jm(locale).format(now),
      ClockFormat.hour24 =>
        showSeconds
            ? DateFormat.Hms(locale).format(now)
            : DateFormat.Hm(locale).format(now),
      ClockFormat.hour12 => DateFormat(
        showSeconds ? 'h:mm:ss a' : 'h:mm a',
        locale,
      ).format(now),
    };
  }

  String _formatDate(BuildContext context, DateTime now) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return formatBarDate(now, locale, style: dateStyle);
  }
}

/// Locale-aware date caption (`Sep 12` in `en_US`, `12. Sept.` in `de_DE`).
/// Kept top-level and pure so unit tests can pin fixed dates.
String formatBarDate(
  DateTime now,
  String locale, {
  ClockDateStyle style = ClockDateStyle.short,
}) {
  return switch (style) {
    ClockDateStyle.short => DateFormat.MMMd(locale).format(now),
    ClockDateStyle.long => DateFormat.MMMMd(locale).format(now),
    ClockDateStyle.weekday => DateFormat.MMMEd(locale).format(now),
  };
}
