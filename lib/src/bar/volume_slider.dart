import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trickster/src/bar/media.dart'
    show formatVolumeLabel, volumeAfterScroll;
import 'package:trickster/src/bar/overlay_panel.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/sink_volume_bloc.dart';
import 'package:trickster/src/state/volume_slider_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/icons.dart';
import 'package:trickster/src/theme/tokens.dart';

/// The track position as a 0..1 level.
double volumeSliderValue(Offset position, double width) =>
    (position.dx / width).clamp(0.0, 1.0);

/// The contents of one volume slider surface: a fullscreen transparent
/// overlay with the slider panel anchored at the strip's inner edge.
/// Tapping the empty area or pressing Escape dismisses it.
class VolumeSliderSurface extends StatefulWidget {
  const VolumeSliderSurface({required this.session, super.key});

  final VolumeSliderSession session;

  @override
  State<VolumeSliderSurface> createState() => _VolumeSliderSurfaceState();
}

class _VolumeSliderSurfaceState extends State<VolumeSliderSurface> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'volume-slider');

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
      context.read<VolumeSliderBloc>().add(const VolumeSliderDismissed());

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The strip's inner edge at the click's cross position, in output
  /// coordinates; mirrors the calendar's anchor.
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
    final anchor = _anchor(MediaQuery.sizeOf(context));
    return Stack(
      fit: StackFit.expand,
      children: [
        // The empty area is the dismissal target; the panel below absorbs
        // its own taps.
        GestureDetector(behavior: HitTestBehavior.opaque, onTap: _dismiss),
        CustomSingleChildLayout(
          delegate: OverlayPanelLayoutDelegate(
            anchor: anchor,
            side: session.side,
          ),
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: _handleKeyEvent,
            child: GestureDetector(
              onTap: () {},
              child: _VolumeSliderPanel(accent: session.accent),
            ),
          ),
        ),
      ],
    );
  }
}

class _VolumeSliderPanel extends StatelessWidget {
  const _VolumeSliderPanel({required this.accent});

  final WallpaperAccent accent;

  @override
  Widget build(BuildContext context) {
    final volume = context.select((SinkVolumeBloc bloc) => bloc.state);
    final step =
        context.select((SettingsBloc bloc) => bloc.state.media.volumeStep) /
        100;
    final color = volume.muted
        ? accent.color
        : ShellMediaColors.lightForeground;
    return DecoratedBox(
      key: const ValueKey<String>('volume-slider-panel'),
      decoration: overlayPanelDecoration(context, accent),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        // The wheel works over the open slider too, at the configured step.
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
            context.read<SinkVolumeBloc>().add(
              SinkVolumeSetRequested(
                volumeAfterScroll(
                  volume.volume,
                  event.scrollDelta.dy < 0 ? step : -step,
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: SizedBox(
            width: 180,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      volumeGlyphFor(volume.volume, muted: volume.muted),
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatVolumeLabel(volume.volume),
                      style: ShellText.systemBarValue,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _VolumeTrack(accent: accent, volume: volume.volume, step: step),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeTrack extends StatelessWidget {
  const _VolumeTrack({
    required this.accent,
    required this.volume,
    required this.step,
  });

  final WallpaperAccent accent;
  final double volume;
  final double step;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        void setFrom(Offset position) {
          context.read<SinkVolumeBloc>().add(
            SinkVolumeSetRequested(volumeSliderValue(position, width)),
          );
        }

        return Semantics(
          slider: true,
          label: context.l10n.mediaVolume,
          value: formatVolumeLabel(volume),
          increasedValue: formatVolumeLabel((volume + step).clamp(0.0, 1.0)),
          decreasedValue: formatVolumeLabel((volume - step).clamp(0.0, 1.0)),
          onIncrease: () => context.read<SinkVolumeBloc>().add(
            SinkVolumeSetRequested((volume + step).clamp(0.0, 1.0)),
          ),
          onDecrease: () => context.read<SinkVolumeBloc>().add(
            SinkVolumeSetRequested((volume - step).clamp(0.0, 1.0)),
          ),
          child: GestureDetector(
            key: const ValueKey<String>('volume-slider-track'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => setFrom(details.localPosition),
            onHorizontalDragUpdate: (details) => setFrom(details.localPosition),
            child: SizedBox(
              height: 24,
              width: width,
              child: CustomPaint(
                painter: _VolumeTrackPainter(accent: accent, volume: volume),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VolumeTrackPainter extends CustomPainter {
  const _VolumeTrackPainter({required this.accent, required this.volume});

  final WallpaperAccent accent;
  final double volume;

  @override
  void paint(Canvas canvas, Size size) {
    const trackHeight = 6.0;
    const radius = Radius.circular(trackHeight / 2);
    final centerY = size.height / 2;
    final track = Rect.fromLTWH(
      0,
      centerY - trackHeight / 2,
      size.width,
      trackHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = ShellMediaColors.glassSurface,
    );
    final level = volume.clamp(0.0, 1.0);
    final filled = size.width * level;
    if (filled > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, centerY - trackHeight / 2, filled, trackHeight),
          radius,
        ),
        Paint()..color = accent.color,
      );
    }
    const knobRadius = 7.0;
    final knobX = filled.clamp(knobRadius, size.width - knobRadius);
    canvas.drawCircle(
      Offset(knobX, centerY),
      knobRadius,
      Paint()..color = accent.color,
    );
    canvas.drawCircle(
      Offset(knobX, centerY),
      knobRadius,
      Paint()
        ..color = ShellMediaColors.darkness
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _VolumeTrackPainter oldDelegate) =>
      oldDelegate.volume != volume || oldDelegate.accent != accent;
}
