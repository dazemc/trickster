import 'package:flutter/widgets.dart';

import '../services/battery.dart';
import '../theme/accent.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class BatteryPill extends StatelessWidget {
  const BatteryPill({required this.accent, required this.status, super.key});

  final WallpaperAccent accent;
  final BatteryStatus status;

  @override
  Widget build(BuildContext context) {
    final capacity = status.capacity ?? 0;
    return SystemBarCard(
      accent: accent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: const Size(18, 10),
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
    final outline = Paint()
      ..color = ShellMediaColors.lightForeground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final body = RRect.fromLTRBR(
      0.5,
      0.5,
      size.width - 2.5,
      size.height - 0.5,
      const Radius.circular(2),
    );
    canvas.drawRRect(body, outline);
    canvas.drawRect(
      Rect.fromLTWH(size.width - 2.2, size.height * 0.28, 1.6, size.height * 0.44),
      Paint()..color = ShellMediaColors.lightForeground,
    );
    final fillWidth = (body.width - 2) * capacity.clamp(0.0, 1.0);
    if (fillWidth > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          body.left + 1,
          body.top + 1,
          body.left + 1 + fillWidth,
          body.bottom - 1,
          const Radius.circular(1),
        ),
        Paint()..color = charging ? ShellTelemetryColors.charging : accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter oldDelegate) {
    return oldDelegate.capacity != capacity ||
        oldDelegate.charging != charging ||
        oldDelegate.accent != accent;
  }
}
