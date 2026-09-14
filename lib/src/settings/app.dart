import 'dart:async';

import 'package:flutter/widgets.dart';

import '../locale.dart';
import '../platform/layer_shell.dart';
import '../theme/tokens.dart';
import 'controller.dart';
import 'pages/appearance.dart';
import 'scope.dart';
import 'settings_theme.dart';

/// Root of the settings application: the same binary in settings mode, its
/// own process and engine, one plain window, no strip surfaces, no bar blocs.
///
/// The engine hosts one non-implicit view, so like the bar it must build a
/// [View] per reported view; a bare widget tree would render nothing.
class TricksterSettingsApp extends StatefulWidget {
  const TricksterSettingsApp({super.key});

  @override
  State<TricksterSettingsApp> createState() => _TricksterSettingsAppState();
}

class _TricksterSettingsAppState extends State<TricksterSettingsApp> {
  late final SettingsAppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SettingsAppController();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    return SettingsAppScope(
      notifier: _controller,
      child: ViewCollection(
        views: [
          for (final view in views)
            View(
              view: view,
              child: TricksterLocalizationScope(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        SettingsColors.backgroundTop,
                        SettingsColors.background,
                      ],
                    ),
                  ),
                  child: const SettingsHome(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The settings shell: header plus the page area. Pages arrive in the
/// following steps; this step proves the mode, window, and design language.
class SettingsHome extends StatelessWidget {
  const SettingsHome({this.onClose, super.key});

  /// Test seam; production closes the native settings window.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = SettingsAppScope.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.settingsTitle,
                      style: ShellText.systemBarValue.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.settingsCaption,
                      style: ShellText.systemBarCaption.copyWith(
                        color: ShellMediaColors.lightForegroundSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SettingsCloseButton(
                onPressed:
                    onClose ??
                    () => unawaited(LayerShell().closeSettingsWindow()),
              ),
            ],
          ),
          if (controller.error != null) ...[
            const SizedBox(height: 16),
            SettingsCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                controller.error!,
                style: ShellText.systemBarCaption.copyWith(
                  color: ShellTelemetryColors.danger,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Expanded(
            child: !controller.loaded
                ? Center(
                    child: Text(
                      l10n.settingsLoading,
                      style: ShellText.systemBarCaption.copyWith(
                        color: ShellMediaColors.lightForegroundSecondary,
                      ),
                    ),
                  )
                : const SingleChildScrollView(child: AppearancePage()),
          ),
        ],
      ),
    );
  }
}
