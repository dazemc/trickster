import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/bar/pill_tooltip.dart';
import 'package:trickster/src/config/settings.dart'
    show MediaMode, MediaOptions;
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/services/mpris.dart';
import 'package:trickster/src/state/media_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';
import 'package:trickster/src/state/visualizer_bloc.dart';
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
    this.bars = MediaOptions.defaultBars,
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

  /// Bars the equalizer mark paints; the analyzer's bands fold into them.
  final int bars;

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
  bool? _visualizerVisible;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVisualizer();
  }

  @override
  void didUpdateWidget(covariant MediaPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A configured change resets the transient cycle.
    if (oldWidget.mode != widget.mode) {
      _mode = widget.mode;
    }
    _syncVisualizer();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Tells the visualizer bloc whether the pill paints the equalizer and
  /// mirrors the current playback flag, so the capture/analysis pair runs
  /// only while its levels are seen.
  void _syncVisualizer() {
    final visible = !widget.vertical && _mode != MediaMode.compact;
    _dispatchPlayback();
    if (_visualizerVisible == visible) {
      return;
    }
    _visualizerVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<VisualizerBloc>().add(
          VisualizerVisibilityChanged(visible: visible),
        );
      }
    });
  }

  void _dispatchPlayback() {
    context.read<VisualizerBloc>().add(
      VisualizerPlaybackChanged(
        playing: context.read<MediaBloc>().state.playing,
      ),
    );
  }

  /// Right-click cycle: the text card, then just the transport keys, then the
  /// full card, back around. The choice is saved, so the document and the
  /// settings application follow it.
  void _cycle() {
    setState(() {
      _mode = switch (_mode) {
        MediaMode.semi => MediaMode.compact,
        MediaMode.compact => MediaMode.full,
        MediaMode.full => MediaMode.semi,
      };
    });
    context.read<SettingsBloc>().add(SettingsMediaModeChanged(_mode));
    _syncVisualizer();
  }

  @override
  Widget build(BuildContext context) {
    // Playback changes feed the visualizer bloc; the initial flag arrives
    // through _syncVisualizer on mount.
    return BlocListener<MediaBloc, MprisPlaybackState>(
      listenWhen: (previous, next) => previous.playing != next.playing,
      listener: (context, state) => _dispatchPlayback(),
      child: _buildPill(context),
    );
  }

  Widget _buildPill(BuildContext context) {
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
                        bars: widget.bars,
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

/// The pill's playing mark: bars painted from the visualizer bloc's band
/// levels. The analyzer runs only while the pill shows them, so the mark
/// steps at the analyzer's ~30 Hz instead of holding the engine at the
/// display rate; with no capture, or under reduced motion, the bars keep
/// their static rest.
class _MediaEqualizer extends StatelessWidget {
  const _MediaEqualizer({required this.bars, required this.color, super.key});

  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return BlocBuilder<VisualizerBloc, VisualizerState>(
      builder: (context, state) {
        final levels = reduceMotion || !state.active
            ? const <double>[]
            : state.levels;
        return RepaintBoundary(
          child: CustomPaint(
            size: Size(equalizerMarkWidth(bars), 14),
            painter: EqualizerPainter(
              levels: equalizerLevels(levels, bars: bars),
              color: color,
            ),
          ),
        );
      },
    );
  }
}

/// The mark's width for [bars] bars: a fixed bar/gap rhythm so the mark looks
/// the same at every count, only longer.
double equalizerMarkWidth(int bars) {
  const barWidth = 2.8;
  const gap = 1.6;
  return bars * barWidth + (bars - 1) * gap;
}

/// Folds the analyzer's bands into the mark's bar count by averaging each
/// bar's slice; an empty band list yields the resting zeroes.
List<double> equalizerLevels(List<double> bands, {int bars = 4}) {
  if (bands.isEmpty) {
    return List<double>.filled(bars, 0);
  }
  return <double>[
    for (var bar = 0; bar < bars; bar++)
      _sliceMean(
        bands,
        bar * bands.length ~/ bars,
        (bar + 1) * bands.length ~/ bars,
      ),
  ];
}

double _sliceMean(List<double> values, int start, int end) {
  if (end <= start) {
    return 0;
  }
  var sum = 0.0;
  for (var index = start; index < end; index++) {
    sum += values[index];
  }
  return sum / (end - start);
}

/// Paints the mark's bars from normalized levels, resting at [_rest] when a
/// bar is quiet.
class EqualizerPainter extends CustomPainter {
  const EqualizerPainter({required this.levels, required this.color});

  static const double _rest = 0.22;

  /// One 0..1 level per bar.
  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final bars = levels.length;
    const gap = 1.6;
    final width = (size.width - gap * (bars - 1)) / bars;
    for (var i = 0; i < bars; i++) {
      final level = _rest + (1 - _rest) * levels[i].clamp(0.0, 1.0);
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
  bool shouldRepaint(covariant EqualizerPainter oldDelegate) {
    return oldDelegate.color != color ||
        !_sameLevels(oldDelegate.levels, levels);
  }

  static bool _sameLevels(List<double> a, List<double> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
