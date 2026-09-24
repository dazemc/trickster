import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/saver.dart';
import 'package:trickster/src/settings/settings_theme.dart';

/// Language page: the catalog the bar and this window follow. `null` keeps
/// the system locale.
class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  DebouncedSaver? _saver;

  @override
  void dispose() {
    _saver?.dispose();
    super.dispose();
  }

  void _apply(SettingsAppBloc controller, String? tag) {
    _saver ??= DebouncedSaver(controller);
    _saver!.apply((settings) => settings.withLocale(tag));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.read<SettingsAppBloc>();
    final current = context.select(
      (SettingsAppBloc bloc) => bloc.state.settings.locale,
    );
    final choices = <(String?, String)>[
      (null, l10n.settingsLanguageSystem),
      ('en', l10n.settingsLanguageEnglish),
      ('zh', l10n.settingsLanguageChinese),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(
          title: l10n.settingsLanguageTitle,
          caption: l10n.settingsLanguageCaption,
        ),
        const SizedBox(height: 20),
        SettingsCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (tag, label) in choices)
                      SettingsChoiceChip(
                        key: ValueKey<String>('language-${tag ?? 'system'}'),
                        label: label,
                        selected: current == tag,
                        onPressed: () => _apply(controller, tag),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SettingsResetButton(
                key: const ValueKey<String>('reset-locale'),
                label: context.l10n.settingsResetOption(
                  l10n.settingsLanguageTitle,
                ),
                enabled: current != null,
                onPressed: () => _apply(controller, null),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
