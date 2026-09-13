import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../state/clock_bloc.dart';
import '../theme/accent.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class ClockPill extends StatelessWidget {
  const ClockPill({required this.accent, super.key});

  final WallpaperAccent accent;

  @override
  Widget build(BuildContext context) {
    return SystemBarCard(
      accent: accent,
      child: BlocBuilder<ClockBloc, ClockState>(
        builder: (context, state) => _ClockRow(accent: accent, now: state.now),
      ),
    );
  }
}

class _ClockRow extends StatelessWidget {
  const _ClockRow({required this.accent, required this.now});

  final WallpaperAccent accent;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(context, now);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatDate(context, now),
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
    );
  }

  String _formatTime(BuildContext context, DateTime now) {
    // Skeleton `jm` follows the locale's own hour cycle: 12h with day
    // period where the locale prefers it, 24h where it does not.
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat.jm(locale).format(now);
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
