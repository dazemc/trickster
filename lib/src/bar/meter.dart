import 'package:flutter/widgets.dart';

import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/motion.dart';
import 'package:trickster/src/theme/tokens.dart';

/// One load meter: a caption tag naming the source, a sparkline of the recent
/// history, and the percentage. Identity comes from the tag, never from the
/// line color alone.
class LoadMeter extends StatelessWidget {
  const LoadMeter({
    required this.accent,
    required this.label,
    required this.current,
    required this.history,
    required this.capacity,
    this.valueColor,
    this.vertical = false,
    super.key,
  });

  static const Key sparklineKey = ValueKey<String>('load-sparkline');

  final WallpaperAccent accent;
  final String label;
  final double? current;
  final List<double> history;
  final int capacity;

  /// Overrides the percent text color when a threshold is crossed.
  final Color? valueColor;

  /// Vertical strips stack the caption over the percent and drop the
  /// sparkline.
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final percent = ((current ?? 0.0) * 100).round();
    final captionColor = accent.captionColor();
    if (vertical) {
      return Semantics(
        label: label,
        value: '$percent%',
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: ShellText.systemBarCaption.copyWith(
                      color: captionColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$percent%',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: ShellText.systemBarValue.copyWith(color: valueColor),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              RepaintBoundary(
                child: CustomPaint(
                  key: sparklineKey,
                  size: const Size(38, 10),
                  painter: _SparklinePainter(
                    history: history,
                    capacity: capacity,
                    accent: accent.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      label: label,
      value: '$percent%',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: Motion.wallpaperReveal,
              curve: Motion.standard,
              style: ShellText.systemBarCaption.copyWith(color: captionColor),
              child: Text(label),
            ),
            const SizedBox(width: 6),
            RepaintBoundary(
              child: CustomPaint(
                key: sparklineKey,
                size: const Size(38, 14),
                painter: _SparklinePainter(
                  history: history,
                  capacity: capacity,
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
                  style: ShellText.systemBarValue.copyWith(color: valueColor),
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
      ),
    );
  }
}

/// Maps [history] (oldest first, 0-1 values) onto sparkline points inside
/// [size]. The newest sample sits on the right edge; a partial history leaves
/// the left side empty so the line grows leftward as samples arrive.
@visibleForTesting
List<Offset> sparklinePoints(List<double> history, Size size, int capacity) {
  if (history.isEmpty || size.isEmpty || capacity < 2) {
    return const <Offset>[];
  }
  final step = size.width / (capacity - 1);
  return List<Offset>.generate(history.length, (index) {
    final fromEnd = history.length - 1 - index;
    return Offset(
      size.width - fromEnd * step,
      size.height * (1.0 - history[index].clamp(0.0, 1.0)),
    );
  }, growable: false);
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.history,
    required this.capacity,
    required this.accent,
  });

  final List<double> history;
  final int capacity;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final points = sparklinePoints(history, size, capacity);
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
    return oldDelegate.history != history ||
        oldDelegate.capacity != capacity ||
        oldDelegate.accent != accent;
  }
}
