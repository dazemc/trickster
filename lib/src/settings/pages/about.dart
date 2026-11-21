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
class AboutPage extends StatefulWidget {
  const AboutPage({this.versionLoader, super.key});

  /// Test seam; production asks the bar's control socket.
  final Future<Map<String, Object?>> Function()? versionLoader;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late Future<Map<String, Object?>> _versions;

  @override
  void initState() {
    super.initState();
    _versions = _load();
  }

  @override
  void didUpdateWidget(covariant AboutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.versionLoader != widget.versionLoader) {
      _versions = _load();
    }
  }

  Future<Map<String, Object?>> _load() async {
    try {
      if (widget.versionLoader != null) {
        return await widget.versionLoader!();
      }
      return await controlRequest(const <String, Object?>{
        'command': 'version',
      });
    } on ControlSocketException {
      return const <String, Object?>{'ok': false};
    } on Object {
      // A host that cannot answer, or a malformed reply, reads as not
      // running instead of surfacing an unhandled future.
      return const <String, Object?>{'ok': false};
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The page renders static versions; it only needs a rebuild once the
    // document loads (the shell already gates on that).
    context.select((SettingsAppBloc bloc) => bloc.state.loaded);
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
            future: _versions,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: ShellText.systemBarCaption.copyWith(
              color: ShellMediaColors.lightForegroundSecondary,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: ShellText.systemBarValue,
          ),
        ),
      ],
    );
  }
}
