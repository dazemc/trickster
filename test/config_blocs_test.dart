import 'dart:ui';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/config/session.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';
import 'package:trickster/src/state/outputs_bloc.dart';
import 'package:trickster/src/state/session_bloc.dart';
import 'package:trickster/src/state/settings_bloc.dart';

void main() {
  group('SettingsBloc', () {
    blocTest<SettingsBloc, BarSettings>(
      'emits loaded settings',
      build: SettingsBloc.new,
      act: (bloc) => bloc.add(
        const SettingsLoaded(BarSettings(revision: 2, modules: ['clock'])),
      ),
      expect: () => [
        const BarSettings(revision: 2, modules: ['clock']),
      ],
    );

    blocTest<SettingsBloc, BarSettings>(
      'applies module and accent changes',
      build: SettingsBloc.new,
      act: (bloc) {
        bloc
          ..add(const SettingsModulesChanged(['clock']))
          ..add(const SettingsAccentChanged(Color(0xffff0000)));
      },
      // BarSettings has no == yet (see suggestions); match fields.
      expect: () => [
        predicate<BarSettings>(
          (s) => s.modules.length == 1 && s.modules.first == 'clock',
        ),
        predicate<BarSettings>(
          (s) =>
              s.modules.length == 1 &&
              s.modules.first == 'clock' &&
              s.accent == const Color(0xffff0000),
        ),
      ],
    );

    test('settings json round-trips', () {
      const settings = BarSettings(
        revision: 3,
        accent: Color(0xffd0bcff),
        modules: ['clock', 'cpu'],
      );
      final decoded = BarSettings.fromJson(
        Map<String, dynamic>.from(settings.toJson()),
      );
      expect(decoded.revision, 3);
      expect(decoded.accent, const Color(0xffd0bcff));
      expect(decoded.modules, ['clock', 'cpu']);
    });
  });

  group('SessionBloc', () {
    blocTest<SessionBloc, SessionConfig>(
      'emits loaded config',
      build: SessionBloc.new,
      act: (bloc) => bloc.add(
        const SessionLoaded(
          SessionConfig(namespace: 'trickster-test'),
        ),
      ),
      expect: () => [
        const SessionConfig(namespace: 'trickster-test'),
      ],
    );

    test('session json round-trips', () {
      const config = SessionConfig(
        layer: TricksterLayer.overlay,
        namespace: 'trickster-test',
        keyboard: TricksterKeyboard.exclusive,
        accent: Color(0xffff0000),
      );
      final decoded = SessionConfig.fromJson(
        Map<String, dynamic>.from(config.toJson()),
      );
      expect(decoded.layer, TricksterLayer.overlay);
      expect(decoded.namespace, 'trickster-test');
      expect(decoded.keyboard, TricksterKeyboard.exclusive);
      expect(decoded.accent, const Color(0xffff0000));
    });
  });

  group('OutputsBloc', () {
    blocTest<OutputsBloc, OutputsConfig>(
      'emits loaded config',
      build: OutputsBloc.new,
      act: (bloc) => bloc.add(
        const OutputsLoaded(
          OutputsConfig(side: SystemBarSide.bottom, thickness: 40),
        ),
      ),
      expect: () => [
        const OutputsConfig(side: SystemBarSide.bottom, thickness: 40),
      ],
    );

    test('outputs json round-trips', () {
      const config = OutputsConfig(
        side: SystemBarSide.left,
        thickness: 48,
        connectors: ['eDP-1'],
      );
      final decoded = OutputsConfig.fromJson(
        Map<String, dynamic>.from(config.toJson()),
      );
      expect(decoded.side, SystemBarSide.left);
      expect(decoded.thickness, 48);
      expect(decoded.connectors, ['eDP-1']);
    });
  });
}
