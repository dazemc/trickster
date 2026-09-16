import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart' show MediaMode;
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/theme/accent.dart';
import 'package:trickster/src/theme/motion.dart';
import 'package:trickster/src/theme/tokens.dart';

/// Inline media pill: now-playing text while idle, transport controls after a
/// tap. Only the fields it paints are selected, so position ticks and
/// `observedAt` churn never rebuild the strip.
class MediaPill extends StatefulWidget {
  const MediaPill({
    required this.accent,
    this.mode = MediaMode.semi,
    this.vertical = false,
    super.key,
  });

  static const double maxTitleWidth = 190;
  static const double maxSecondaryWidth = 130;

  /// The equalizer mark painted in full and semi modes.
  static const Key equalizerKey = ValueKey<String>('media-equalizer');

  final WallpaperAccent accent;

  /// The configured display mode; tapping cycles transiently from it and a
  /// relaunch returns to it.
  final MediaMode mode;

  /// Vertical strips show only the transport controls, stacked and always
  /// visible.
  final bool vertical;

  @override
  State<MediaPill> createState() => _MediaPillState();
}

class _MediaPillState extends State<MediaPill> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'media-pill');
  late var _mode = widget.mode;
  var _hovered = false;
  var _focused = false;

  @override
  void didUpdateWidget(covariant MediaPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A configured change resets the transient cycle.
    if (oldWidget.mode != widget.mode) {
      _mode = widget.mode;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Transient cycle: the text card, then just the transport keys, then the
  /// full card, back around.
  void _cycle() => setState(() {
    _mode = switch (_mode) {
      MediaMode.semi => MediaMode.compact,
      MediaMode.compact => MediaMode.full,
      MediaMode.full => MediaMode.semi,
    };
  });

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
    final showText = _mode == MediaMode.full;
    final showSecondary = showText;
    // The equalizer is the horizontal strip's playing mark; compact keeps
    // the keys alone and vertical strips are keys-only too.
    final showEqualizer = !widget.vertical && _mode != MediaMode.compact;
    const showControls = true;
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
    final controls = [
      _MediaControlButton(
        compact: widget.vertical,
        label: l10n.mediaPrevious,
        glyph: LucideIcons.skipBack,
        color: widget.accent.color,
        enabled: media.canGoPrevious,
        onPressed: bloc.previous,
      ),
      const SizedBox(width: 4),
      _MediaControlButton(
        compact: widget.vertical,
        label: media.playing ? l10n.mediaPause : l10n.mediaPlay,
        glyph: media.playing ? LucideIcons.pause : LucideIcons.play,
        color: widget.accent.color,
        enabled: media.playing ? media.canPause : media.canPlay,
        prominent: true,
        onPressed: bloc.playPause,
      ),
      const SizedBox(width: 4),
      _MediaControlButton(
        compact: widget.vertical,
        label: l10n.mediaNext,
        glyph: LucideIcons.skipForward,
        color: widget.accent.color,
        enabled: media.canGoNext,
        onPressed: bloc.next,
      ),
    ];
    if (widget.vertical) {
      // No card-level tap and no ExcludeSemantics: the transport buttons'
      // own semantics are the interaction.
      return PillTooltip(
        accent: widget.accent,
        label: value,
        child: Semantics(
          label: label,
          value: value,
          hint: l10n.mediaHint,
          child: SystemBarCard(
            accent: widget.accent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                controls[0],
                const SizedBox(width: 2),
                controls[2],
                const SizedBox(width: 2),
                controls[4],
              ],
            ),
          ),
        ),
      );
    }
    // Hand-rolled rather than a TricksterActionCard: its ExcludeSemantics
    // would swallow the transport buttons' own semantics.
    return PillTooltip(
      accent: widget.accent,
      label: value,
      child: Semantics(
        button: true,
        label: label,
        value: value,
        hint: l10n.mediaHint,
        onTap: _cycle,
        child: FocusableActionDetector(
          focusNode: _focusNode,
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (value) => setState(() => _hovered = value),
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (intent) {
                _cycle();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The transport buttons own the left button; the right button
            // cycles the display mode anywhere on the pill.
            onSecondaryTap: _cycle,
            child: SystemBarCard(
              accent: widget.accent,
              highlighted: _hovered || _focused,
              focused: _focused,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showEqualizer) ...[
                    ExcludeSemantics(
                      child: _MediaEqualizer(
                        key: MediaPill.equalizerKey,
                        playing: media.playing,
                        color: widget.accent.color,
                      ),
                    ),
                    if (showText) const SizedBox(width: 7),
                  ],
                  if (showText)
                    ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                          if (showSecondary &&
                              secondary.isNotEmpty &&
                              secondary != title) ...[
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
                                  color:
                                      ShellMediaColors.lightForegroundSecondary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (showControls) ...[
                    if (showText || showEqualizer) const SizedBox(width: 9),
                    ...controls,
                  ],
                ],
              ),
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
    this.compact = false,
  });

  final String label;
  final IconData glyph;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;
  final bool prominent;
  final bool compact;

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
              width: widget.compact ? 16 : 20,
              height: widget.compact ? 16 : 20,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.glyph,
                size: widget.compact ? 12 : 14,
                color: glyphColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pill's playing mark: synthetic equalizer bars that dance while the
/// player is playing and settle when it pauses. MPRIS carries no spectrum
/// data, so the motion is decorative, and the controller only runs while
/// playback does.
class _MediaEqualizer extends StatefulWidget {
  const _MediaEqualizer({
    required this.playing,
    required this.color,
    super.key,
  });

  final bool playing;
  final Color color;

  @override
  State<_MediaEqualizer> createState() => _MediaEqualizerState();
}

class _MediaEqualizerState extends State<_MediaEqualizer> {
  static const List<double> _phase = <double>[0.0, 0.37, 0.71, 0.19];
  static const List<double> _speed = <double>[1.0, 1.6, 1.25, 0.8];

  /// The bars step at ~16 fps instead of the display rate: the mark reads as
  /// motion, and a playing track never holds the engine at 60 fps for a
  /// decorative widget.
  static const Duration _step = Duration(milliseconds: 62);

  Timer? _timer;
  var _phaseValue = 0.0;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant _MediaEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) {
      _syncTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _syncTimer() {
    _timer?.cancel();
    _timer = null;
    if (!widget.playing) {
      _phaseValue = 0;
      return;
    }
    _timer = Timer.periodic(_step, (_) {
      if (mounted) {
        setState(
          () => _phaseValue = (_phaseValue + _step.inMilliseconds / 900) % 1.0,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(16, 14),
        painter: _EqualizerPainter(
          phase: reduceMotion ? 0 : _phaseValue,
          playing: !reduceMotion && widget.playing,
          color: widget.color,
          phases: _phase,
          speeds: _speed,
        ),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  const _EqualizerPainter({
    required this.phase,
    required this.playing,
    required this.color,
    required this.phases,
    required this.speeds,
  });

  static const double _rest = 0.22;

  final double phase;
  final bool playing;
  final Color color;
  final List<double> phases;
  final List<double> speeds;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final bars = phases.length;
    const gap = 1.6;
    final width = (size.width - gap * (bars - 1)) / bars;
    for (var i = 0; i < bars; i++) {
      final t = (phase * speeds[i] + phases[i]) % 1.0;
      final level = playing
          ? 0.3 + 0.7 * (0.5 + 0.5 * math.sin(2 * math.pi * t))
          : _rest;
      final height = (size.height * level).clamp(2.0, size.height);
      final left = i * (width + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, size.height - height, width, height),
          const Radius.circular(1.2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.playing != playing ||
      oldDelegate.color != color;
}
