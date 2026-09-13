import 'package:flutter/widgets.dart';

import '../services/cpu.dart';
import '../theme/accent.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'pill.dart';

class CpuPill extends StatelessWidget {
  const CpuPill({required this.accent, required this.sample, super.key});

  static const Key sparklineKey = ValueKey<String>('cpu-sparkline');

  final WallpaperAccent accent;
  final CpuSample sample;

  @override
  Widget build(BuildContext context) {
    final percent = ((sample.current ?? 0) * 100).round();
    final captionColor = accent.captionColor();
    return SystemBarCard(
      accent: accent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedDefaultTextStyle(
            duration: Motion.wallpaperReveal,
            curve: Motion.standard,
            style: ShellText.systemBarCaption.copyWith(color: captionColor),
            child: const Text('CPU'),
          ),
          const SizedBox(width: 6),
          RepaintBoundary(
            child: CustomPaint(
              key: sparklineKey,
              size: const Size(38, 14),
              painter: _SparklinePainter(
                history: sample.history,
                accent: accent.color,
              ),
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            width: 34,
            child: Text.rich(
              TextSpan(
                text: '$percent',
                style: ShellText.systemBarValue,
                children: [
                  TextSpan(
                    text: '%',
                    style: ShellText.systemBarCaption.copyWith(
                      color: captionColor,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Maps [history] (oldest first, 0-1 values) onto sparkline points inside
/// [size]. The newest sample sits on the right edge; a partial history leaves
/// the left side empty so the line grows leftward as samples arrive.
@visibleForTesting
List<Offset> sparklinePoints(List<double> history, Size size) {
  if (history.isEmpty || size.isEmpty) {
    return const <Offset>[];
  }
  final step = size.width / (CpuSample.capacity - 1);
  return List<Offset>.generate(history.length, (index) {
    final fromEnd = history.length - 1 - index;
    return Offset(
      size.width - fromEnd * step,
      size.height * (1.0 - history[index].clamp(0.0, 1.0)),
    );
  }, growable: false);
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.history, required this.accent});

  final List<double> history;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final points = sparklinePoints(history, size);
    if (points.length < 2) {
      return;
    }
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            accent.withValues(alpha: 0.35),
            accent.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.history != history || oldDelegate.accent != accent;
  }
}
