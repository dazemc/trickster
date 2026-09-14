import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trickster/src/cli.dart';
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/platform/control_socket.dart';
import 'package:trickster/src/settings/bloc.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/theme/tokens.dart';

/// About page: the binary version, the running bar's version and control
/// protocol, and the repository link. Versions degrade to "not running"
/// when no bar answers.
class AboutPage extends StatelessWidget {
  const AboutPage({this.versionLoader, super.key});

  /// Test seam; production asks the bar's control socket.
  final Future<Map<String, Object?>> Function()? versionLoader;

  Future<Map<String, Object?>> _load() async {
    if (versionLoader != null) {
      return versionLoader!();
    }
    try {
      return await controlRequest(const <String, Object?>{
        'command': 'version',
      });
    } on ControlSocketException {
      return const <String, Object?>{'ok': false};
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    context.watch<SettingsAppBloc>(); // keep the page scoped to the controller
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(
          title: l10n.settingsAboutTitle,
          caption: l10n.settingsAboutCaption,
        ),
        const SizedBox(height: 20),
        SettingsCard(
          child: FutureBuilder<Map<String, Object?>>(
            future: _load(),
            builder: (context, snapshot) {
              final reply = snapshot.data ?? const <String, Object?>{};
              final bar = reply['ok'] == true && reply['version'] is String
                  ? '${reply['version']}'
                  : l10n.settingsAboutNotRunning;
              final protocol = reply['protocol'] is int
                  ? '${reply['protocol']}'
                  : '—';
              return Column(
                children: [
                  _AboutRow(
                    label: l10n.settingsAboutVersion,
                    value: Cli.appVersion,
                  ),
                  const SizedBox(height: 10),
                  _AboutRow(label: l10n.settingsAboutBar, value: bar),
                  const SizedBox(height: 10),
                  _AboutRow(label: l10n.settingsAboutProtocol, value: protocol),
                  const SizedBox(height: 10),
                  _AboutRow(
                    label: l10n.settingsAboutRepository,
                    value: 'github.com/dazemc/trickster',
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: ShellText.systemBarCaption.copyWith(
              color: ShellMediaColors.lightForegroundSecondary,
            ),
          ),
        ),
        Text(value, style: ShellText.systemBarValue),
      ],
    );
  }
}
