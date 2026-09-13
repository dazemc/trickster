import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

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
      child: _ClockModule(accent: accent),
    );
  }
}

class _ClockModule extends StatefulWidget {
  const _ClockModule({required this.accent});

  final WallpaperAccent accent;

  @override
  State<_ClockModule> createState() => _ClockModuleState();
}

class _ClockModuleState extends State<_ClockModule> {
  DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    _timer = Timer(next.difference(now), () {
      if (!mounted) {
        return;
      }
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(context, _now);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatDate(_now),
          style: ShellText.systemBarCaption.copyWith(
            color: widget.accent.captionColor(),
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

  String _formatDate(DateTime now) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[now.month - 1]} ${now.day}';
  }
}
