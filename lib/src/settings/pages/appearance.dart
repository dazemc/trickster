import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/color_format.dart';
import 'package:trickster/src/settings/color_wheel.dart';
import 'package:trickster/src/settings/controller.dart';
import 'package:trickster/src/settings/saver.dart';
import 'package:trickster/src/settings/scope.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/state/wallpaper_accent.dart';
import 'package:trickster/src/theme/motion.dart';
import 'package:trickster/src/theme/tokens.dart';
import 'package:trickster/src/theme/wallpaper_accent.dart';

/// Denial's accent presets, starting from the shell's default.
const List<Color> accentPresets = <Color>[
  ShellBrandColors.defaultAccent,
  Color(0xff8ab4ff),
  Color(0xff78dce8),
  Color(0xff8ee6c1),
  Color(0xffffd166),
  Color(0xffff9f6b),
  Color(0xffff6b6b),
  Color(0xffff8ad8),
];

/// Appearance page: preset swatches plus the HSV wheel, writing `accent`.
/// Saves are debounced so dragging the wheel writes once per gesture.
class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  DebouncedSaver? _saver;

  @override
  void dispose() {
    _saver?.dispose();
    super.dispose();
  }

  void _apply(SettingsAppController controller, Color? accent) {
    _saver ??= DebouncedSaver(controller);
    _saver!.apply((settings) => settings.withAccent(accent));
  }

  void _applySource(SettingsAppController controller, AccentSource source) {
    _saver ??= DebouncedSaver(controller);
    _saver!.apply((settings) => settings.copyWith(accentSource: source));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    final accent = controller.settings.accent ?? ShellBrandColors.defaultAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(
          title: l10n.settingsAppearanceTitle,
          caption: l10n.settingsAppearanceCaption,
        ),
        const SizedBox(height: 20),
        SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settingsAccentSource,
                      style: ShellText.systemBarCaption.copyWith(
                        color: ShellMediaColors.lightForegroundSecondary,
                      ),
                    ),
                  ),
                  SettingsResetButton(
                    key: const ValueKey<String>('reset-accent-source'),
                    label: l10n.settingsResetOption(l10n.settingsAccentSource),
                    enabled:
                        controller.settings.accentSource != AccentSource.custom,
                    onPressed: () =>
                        _applySource(controller, AccentSource.custom),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SettingsChoiceChip(
                    key: const ValueKey<String>('accent-source-custom'),
                    label: l10n.settingsAccentSourceCustom,
                    selected:
                        controller.settings.accentSource == AccentSource.custom,
                    onPressed: () =>
                        _applySource(controller, AccentSource.custom),
                  ),
                  SettingsChoiceChip(
                    key: const ValueKey<String>('accent-source-wallpaper'),
                    label: l10n.settingsAccentSourceWallpaper,
                    selected:
                        controller.settings.accentSource ==
                        AccentSource.wallpaper,
                    onPressed: () =>
                        _applySource(controller, AccentSource.wallpaper),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (controller.settings.accentSource == AccentSource.wallpaper)
                _WallpaperAccents(
                  candidates:
                      WallpaperAccentScope.maybeOf(context)?.candidates ??
                      const <Color>[],
                  picked: colorFromHex(controller.settings.accentWallpaperPick),
                  onPick: (color) {
                    final hex = formatOpaqueColorHex(color);
                    _saver ??= DebouncedSaver(controller);
                    _saver!.apply(
                      (settings) => settings.copyWith(accentWallpaperPick: hex),
                    );
                  },
                  onReset: () {
                    _saver ??= DebouncedSaver(controller);
                    _saver!.apply(
                      (settings) => settings.withAccentWallpaperPick(null),
                    );
                  },
                )
              else ...[
                Text(
                  l10n.settingsAccentPresets,
                  style: ShellText.systemBarCaption.copyWith(
                    color: ShellMediaColors.lightForegroundSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final preset in accentPresets)
                      _SwatchButton(
                        key: ValueKey<String>(
                          'accent-preset-${formatOpaqueColorHex(preset)}',
                        ),
                        color: preset,
                        selected: preset.toARGB32() == accent.toARGB32(),
                        onPressed: () => _apply(controller, preset),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 176,
                      child: HsvColorWheel(
                        color: accent,
                        onChanged: (color) => _apply(controller, color),
                      ),
                    ),
                    const SizedBox(width: 28),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          formatOpaqueColorHex(accent),
                          style: ShellText.systemBarValue.copyWith(
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SettingsResetButton(
                          key: const ValueKey<String>('reset-accent'),
                          label: l10n.settingsResetOption(
                            l10n.settingsAccentColor,
                          ),
                          enabled: controller.settings.accent != null,
                          onPressed: () => _apply(controller, null),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// With the wallpaper as the accent source the wheel and presets would
/// fight the sampler; the page lists the wallpaper's candidate accents and
/// the picked one feeds the bar.
class _WallpaperAccents extends StatelessWidget {
  const _WallpaperAccents({
    required this.candidates,
    required this.picked,
    required this.onPick,
    required this.onReset,
  });

  final List<Color> candidates;
  final Color? picked;
  final ValueChanged<Color> onPick;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active = picked == null
        ? (candidates.isEmpty ? null : candidates.first)
        : closestAccentCandidate(candidates, picked!) ??
              (candidates.isEmpty ? null : candidates.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.settingsAccentWallpaperTitle,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellMediaColors.lightForegroundSecondary,
                ),
              ),
            ),
            SettingsResetButton(
              key: const ValueKey<String>('reset-wallpaper-pick'),
              label: l10n.settingsResetOption(
                l10n.settingsAccentWallpaperTitle,
              ),
              enabled: picked != null,
              onPressed: onReset,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (candidates.isEmpty)
          Text(
            l10n.settingsAccentWallpaperEmpty,
            style: ShellText.systemBarCaption.copyWith(
              color: ShellMediaColors.lightForegroundSecondary,
            ),
          )
        else
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              for (final candidate in candidates)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SwatchButton(
                      key: ValueKey<String>(
                        'wallpaper-accent-${formatOpaqueColorHex(candidate)}',
                      ),
                      color: candidate,
                      selected: candidate.toARGB32() == active?.toARGB32(),
                      onPressed: () => onPick(candidate),
                    ),
                    const SizedBox(width: 8),
                    _CopyHexButton(hex: formatOpaqueColorHex(candidate)),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

/// The hex caption next to a candidate: tap to copy it.
class _CopyHexButton extends StatefulWidget {
  const _CopyHexButton({required this.hex});

  final String hex;

  @override
  State<_CopyHexButton> createState() => _CopyHexButtonState();
}

class _CopyHexButtonState extends State<_CopyHexButton> {
  Timer? _reset;
  var _copied = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    unawaited(Clipboard.setData(ClipboardData(text: widget.hex)));
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.settingsCopyHex(widget.hex),
      onTap: _copy,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _copy,
            child: Text(
              _copied ? l10n.settingsCopied : widget.hex,
              style: ShellText.systemBarValue.copyWith(
                color: _copied
                    ? ShellTelemetryColors.nominal
                    : ShellMediaColors.lightForegroundSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwatchButton extends StatefulWidget {
  const _SwatchButton({
    required this.color,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SwatchButton> createState() => _SwatchButtonState();
}

class _SwatchButtonState extends State<_SwatchButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scale = _hovered ? 1.12 : 1.0;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: formatOpaqueColorHex(widget.color),
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: AnimatedScale(
              duration: Motion.pill,
              curve: Motion.standard,
              scale: scale,
              child: AnimatedContainer(
                duration: Motion.pill,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  border: Border.all(
                    color: widget.selected
                        ? ShellMediaColors.lightForeground
                        : SettingsColors.outline,
                    width: widget.selected ? 2.0 : 1.0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
