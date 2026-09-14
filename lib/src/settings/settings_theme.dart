import 'package:flutter/widgets.dart';

import '../locale.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';

/// The settings window's surface palette: the strip's glass language at
/// window scale, without Material scaffolding.
abstract final class SettingsColors {
  static const Color background = Color(0xff0b0b12);
  static const Color backgroundTop = Color(0xff14141f);
  static const Color surface = Color(0xff171722);
  static const Color surfaceHigh = Color(0xff1f1f2c);
  static const Color outline = Color(0x22ffffff);
}

/// One panel in the settings window, mirroring the strip's pill fills.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SettingsColors.surface,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        border: Border.all(color: SettingsColors.outline),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// The window's close control. The compositor tiles this window, so it may
/// draw no decorations at all; the app carries its own.
class SettingsCloseButton extends StatefulWidget {
  const SettingsCloseButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  State<SettingsCloseButton> createState() => _SettingsCloseButtonState();
}

class _SettingsCloseButtonState extends State<SettingsCloseButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.settingsClose,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: Motion.pill,
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hovered
                    ? SettingsColors.surfaceHigh
                    : SettingsColors.surface,
                border: Border.all(color: SettingsColors.outline),
              ),
              child: const Center(
                child: CustomPaint(
                  size: Size(10, 10),
                  painter: _ClosePainter(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClosePainter extends CustomPainter {
  const _ClosePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ShellMediaColors.lightForegroundSecondary
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset.zero, Offset(size.width, size.height), paint)
      ..drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _ClosePainter oldDelegate) => false;
}

/// A small text button in the settings window.
class SettingsButton extends StatefulWidget {
  const SettingsButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  State<SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<SettingsButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: Motion.pill,
              curve: Motion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _hovered
                    ? SettingsColors.surfaceHigh
                    : SettingsColors.surface,
                borderRadius: const BorderRadius.all(Radius.circular(999)),
                border: Border.all(color: SettingsColors.outline),
              ),
              child: Text(widget.label, style: ShellText.systemBarCaption),
            ),
          ),
        ),
      ),
    );
  }
}

/// A section heading inside the settings window.
class SettingsHeading extends StatelessWidget {
  const SettingsHeading({required this.title, this.caption, super.key});

  final String title;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: ShellText.systemBarValue.copyWith(fontSize: 15)),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption!,
            style: ShellText.systemBarCaption.copyWith(
              color: ShellMediaColors.lightForegroundSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
