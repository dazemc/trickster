import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../config/settings.dart';
import '../locale.dart';
import '../state/clock_bloc.dart';
import '../theme/accent.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class ClockPill extends StatelessWidget {
  const ClockPill({
    required this.accent,
    this.format = ClockFormat.locale,
    super.key,
  });

  final WallpaperAccent accent;
  final ClockFormat format;

  @override
  Widget build(BuildContext context) {
    return SystemBarCard(
      accent: accent,
      child: BlocBuilder<ClockBloc, ClockState>(
        builder: (context, state) =>
            _ClockRow(accent: accent, now: state.now, format: format),
      ),
    );
  }
}

class _ClockRow extends StatelessWidget {
  const _ClockRow({
    required this.accent,
    required this.now,
    required this.format,
  });

  final WallpaperAccent accent;
  final DateTime now;
  final ClockFormat format;

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(context, now);
    final date = _formatDate(context, now);
    return Semantics(
      label: context.l10n.clockTitle,
      value: '$date, $time',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              date,
              style: ShellText.systemBarCaption.copyWith(
                color: accent.captionColor(),
              ),
            ),
            const SizedBox(width: 8),
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
                style: ShellText.systemBarValue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, DateTime now) {
    // The locale default follows the locale's own hour cycle: 12h with day
    // period where the locale prefers it, 24h where it does not.
    final locale = Localizations.localeOf(context).toLanguageTag();
    return switch (format) {
      ClockFormat.locale => DateFormat.jm(locale).format(now),
      ClockFormat.hour24 => DateFormat.Hm(locale).format(now),
      ClockFormat.hour12 => DateFormat('h:mm a', locale).format(now),
    };
  }

  String _formatDate(BuildContext context, DateTime now) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return formatBarDate(now, locale);
  }
}

/// Locale-aware date caption (`Sep 12` in `en_US`, `12. Sept.` in `de_DE`).
/// Kept top-level and pure so unit tests can pin fixed dates.
String formatBarDate(DateTime now, String locale) {
  return DateFormat.MMMd(locale).format(now);
}
