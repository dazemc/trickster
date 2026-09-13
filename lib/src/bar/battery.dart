import 'package:flutter/widgets.dart';

import '../locale.dart';
import '../services/battery.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class BatteryPill extends StatelessWidget {
  const BatteryPill({
    required this.accent,
    required this.status,
    required this.onPressed,
    super.key,
  });

  static const Key gaugeKey = ValueKey<String>('battery-gauge');

  final WallpaperAccent accent;
  final BatteryStatus status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final capacity = status.capacity ?? 0;
    final state = status.charging
        ? l10n.batteryCharging
        : l10n.batteryDischarging;
    return TricksterActionCard(
      accent: accent,
      label:
          '${l10n.batteryTitle}, '
          '${l10n.batteryStateAndPercent(state, capacity)}',
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            key: gaugeKey,
            size: const Size(24, 14),
            painter: _BatteryPainter(
              capacity: capacity / 100.0,
              charging: status.charging,
              accent: accent.color,
            ),
          ),
          const SizedBox(width: 8),
          Text('$capacity%', style: ShellText.systemBarValue),
        ],
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter({
    required this.capacity,
    required this.charging,
    required this.accent,
  });

  final double capacity;
  final bool charging;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.75, 1.25, size.width - 4.0, size.height - 2.5),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..color = ShellMediaColors.lightForeground
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width - 2.55,
          size.height * 0.34,
          1.8,
          size.height * 0.32,
        ),
        const Radius.circular(0.8),
      ),
      Paint()..color = ShellMediaColors.lightForeground,
    );
    final fillWidth = (body.width - 4.0) * capacity.clamp(0.0, 1.0);
    if (fillWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            body.left + 2.0,
            body.top + 2.0,
            fillWidth,
            body.height - 4.0,
          ),
          const Radius.circular(1.5),
        ),
        Paint()..color = charging ? ShellTelemetryColors.charging : accent,
      );
    }
    if (charging) {
      final center = body.center;
      final bolt = Path()
        ..moveTo(center.dx + 0.6, body.top + 1.7)
        ..lineTo(center.dx - 3.0, center.dy + 0.4)
        ..lineTo(center.dx - 0.6, center.dy + 0.4)
        ..lineTo(center.dx - 1.5, body.bottom - 1.6)
        ..lineTo(center.dx + 3.0, center.dy - 0.8)
        ..lineTo(center.dx + 0.5, center.dy - 0.8)
        ..close();
      canvas.drawPath(bolt, Paint()..color = ShellMediaColors.lightForeground);
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter oldDelegate) {
    return oldDelegate.capacity != capacity ||
        oldDelegate.charging != charging ||
        oldDelegate.accent != accent;
  }
}
