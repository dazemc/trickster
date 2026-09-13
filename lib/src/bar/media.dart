import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../locale.dart';
import '../state/media_bloc.dart';
import '../theme/accent.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'pill.dart';

/// Inline media pill: now-playing text while idle, transport controls after a
/// tap. Only the fields it paints are selected, so position ticks and
/// `observedAt` churn never rebuild the strip.
class MediaPill extends StatefulWidget {
  const MediaPill({required this.accent, super.key});

  static const double maxTitleWidth = 190;
  static const double maxSecondaryWidth = 130;

  final WallpaperAccent accent;

  @override
  State<MediaPill> createState() => _MediaPillState();
}

class _MediaPillState extends State<MediaPill> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'media-pill');
  var _expanded = false;
  var _hovered = false;
  var _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final media = context.select((MediaBloc bloc) {
      final state = bloc.state;
      return (
        playing: state.playing,
        title: state.title,
        artist: state.artistLabel,
        album: state.album,
        identity: state.identity,
        canGoPrevious: state.canGoPrevious,
        canGoNext: state.canGoNext,
        canPlay: state.canPlay,
        canPause: state.canPause,
      );
    });
    final secondary = media.artist.isNotEmpty
        ? media.artist
        : media.album.isNotEmpty
        ? media.album
        : media.identity;
    final title = media.title.isNotEmpty ? media.title : secondary;
    final bloc = context.read<MediaBloc>();
    final l10n = context.l10n;
    final label = l10n.mediaControls;
    final value = [
      if (title.isNotEmpty) title,
      if (secondary.isNotEmpty && secondary != title) secondary,
    ].join(', ');
    // Hand-rolled rather than a TricksterActionCard: its ExcludeSemantics
    // would swallow the transport buttons' own semantics.
    return Semantics(
      button: true,
      label: label,
      value: value,
      hint: l10n.mediaHint,
      onTap: _toggle,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              _toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: SystemBarCard(
            accent: widget.accent,
            highlighted: _hovered || _focused,
            focused: _focused,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomPaint(
                        size: const Size(14, 14),
                        painter: _MediaIndicatorPainter(
                          playing: media.playing,
                          color: widget.accent.color,
                        ),
                      ),
                      const SizedBox(width: 7),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: MediaPill.maxTitleWidth,
                        ),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ShellText.systemBarValue,
                        ),
                      ),
                      if (secondary.isNotEmpty && secondary != title) ...[
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: MediaPill.maxSecondaryWidth,
                          ),
                          child: Text(
                            secondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ShellText.systemBarCaption.copyWith(
                              color: ShellMediaColors.lightForegroundSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_expanded) ...[
                  const SizedBox(width: 9),
                  _MediaControlButton(
                    label: l10n.mediaPrevious,
                    glyph: _TransportGlyph.previous,
                    color: widget.accent.color,
                    enabled: media.canGoPrevious,
                    onPressed: bloc.previous,
                  ),
                  const SizedBox(width: 4),
                  _MediaControlButton(
                    label: media.playing ? l10n.mediaPause : l10n.mediaPlay,
                    glyph: media.playing
                        ? _TransportGlyph.pause
                        : _TransportGlyph.play,
                    color: widget.accent.color,
                    enabled: media.playing ? media.canPause : media.canPlay,
                    prominent: true,
                    onPressed: bloc.playPause,
                  ),
                  const SizedBox(width: 4),
                  _MediaControlButton(
                    label: l10n.mediaNext,
                    glyph: _TransportGlyph.next,
                    color: widget.accent.color,
                    enabled: media.canGoNext,
                    onPressed: bloc.next,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaControlButton extends StatefulWidget {
  const _MediaControlButton({
    required this.label,
    required this.glyph,
    required this.color,
    required this.enabled,
    required this.onPressed,
    this.prominent = false,
  });

  final String label;
  final _TransportGlyph glyph;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;
  final bool prominent;

  @override
  State<_MediaControlButton> createState() => _MediaControlButtonState();
}

class _MediaControlButtonState extends State<_MediaControlButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    final glyphColor = enabled
        ? widget.prominent
              ? widget.color
              : ShellMediaColors.lightForeground
        : ShellMediaColors.lightForegroundSecondary.withValues(alpha: 0.45);
    final background = !enabled
        ? ShellMediaColors.glassSurface
        : widget.prominent
        ? widget.color.withValues(alpha: 0.20)
        : _hovered
        ? widget.color.withValues(alpha: 0.18)
        : ShellMediaColors.glassSurface;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: enabled ? (_) => setState(() => _hovered = true) : null,
          onExit: enabled ? (_) => setState(() => _hovered = false) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (enabled) {
                widget.onPressed();
              }
            },
            child: AnimatedContainer(
              duration: Motion.pill,
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
              ),
              child: CustomPaint(
                painter: _TransportPainter(
                  glyph: widget.glyph,
                  color: glyphColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TransportGlyph { previous, play, pause, next }

class _TransportPainter extends CustomPainter {
  const _TransportPainter({required this.glyph, required this.color});

  final _TransportGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;
    switch (glyph) {
      case _TransportGlyph.play:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.36, h * 0.22)
            ..lineTo(w * 0.36, h * 0.78)
            ..lineTo(w * 0.78, h * 0.5)
            ..close(),
          paint,
        );
      case _TransportGlyph.pause:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.32, h * 0.22, w * 0.13, h * 0.56),
            const Radius.circular(1.4),
          ),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.55, h * 0.22, w * 0.13, h * 0.56),
            const Radius.circular(1.4),
          ),
          paint,
        );
      case _TransportGlyph.next:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.26, h * 0.24)
            ..lineTo(w * 0.26, h * 0.76)
            ..lineTo(w * 0.62, h * 0.5)
            ..close(),
          paint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.66, h * 0.24, w * 0.12, h * 0.52),
            const Radius.circular(1.4),
          ),
          paint,
        );
      case _TransportGlyph.previous:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.22, h * 0.24, w * 0.12, h * 0.52),
            const Radius.circular(1.4),
          ),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.74, h * 0.24)
            ..lineTo(w * 0.74, h * 0.76)
            ..lineTo(w * 0.38, h * 0.5)
            ..close(),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _TransportPainter oldDelegate) {
    return oldDelegate.glyph != glyph || oldDelegate.color != color;
  }
}

class _MediaIndicatorPainter extends CustomPainter {
  const _MediaIndicatorPainter({required this.playing, required this.color});

  final bool playing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (playing) {
      const extents = <(double, double)>[(1.0, 6.0), (5.8, 11.0), (10.6, 8.0)];
      for (final (left, height) in extents) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, 13.0 - height, 2.4, height),
            const Radius.circular(1.2),
          ),
          paint,
        );
      }
      return;
    }
    canvas.drawCircle(
      Offset(size.width * 0.34, size.height * 0.72),
      size.width * 0.19,
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.48,
          size.height * 0.22,
          1.7,
          size.height * 0.5,
        ),
        const Radius.circular(0.8),
      ),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.48, size.height * 0.22)
        ..lineTo(size.width * 0.82, size.height * 0.34)
        ..lineTo(size.width * 0.48, size.height * 0.46)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _MediaIndicatorPainter oldDelegate) {
    return oldDelegate.playing != playing || oldDelegate.color != color;
  }
}
