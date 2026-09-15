import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/cli.dart';
import 'package:trickster/src/config/key_value.dart';
import 'package:trickster/src/config/session.dart';
import 'package:trickster/src/config/settings.dart';
import 'package:trickster/src/layout/system_bar.dart';

void main() {
  group('KeyValueDocument', () {
    test('parses pairs and skips comments', () {
      const source = '# comment\nA=1\n\nB = two \n';
      final document = KeyValueDocument.parse(source);
      expect(document['A'], '1');
      expect(document['B'], 'two');
      expect(document['missing'], isNull);
    });

    test('rejects lines without a separator', () {
      expect(() => KeyValueDocument.parse('nope'), throwsFormatException);
      expect(() => KeyValueDocument.parse('=x'), throwsFormatException);
    });
  });

  group('OutputsConfig', () {
    test('defaults to a top 32 strip', () {
      const config = OutputsConfig();
      expect(config.side, SystemBarSide.top);
      expect(config.thickness, 32);
      expect(config.active, isTrue);
    });

    test('parses Denial grammar', () {
      final config = OutputsConfig.parse('system_bar=bottom,40,eDP-1\n');
      expect(config.side, SystemBarSide.bottom);
      expect(config.thickness, 40);
      expect(config.hosts('eDP-1'), isTrue);
      expect(config.hosts('DP-1'), isFalse);
    });

    test('hidden disables the strip', () {
      final config = OutputsConfig.parse('system_bar=hidden\n');
      expect(config.side, SystemBarSide.hidden);
      expect(config.active, isFalse);
    });

    test('rejects unknown sides and bad thickness', () {
      expect(
        () => OutputsConfig.parse('system_bar=diagonal,32\n'),
        throwsFormatException,
      );
      expect(
        () => OutputsConfig.parse('system_bar=top,0\n'),
        throwsFormatException,
      );
    });
  });

  group('SessionConfig', () {
    test('parses machine overrides', () {
      const source =
          'TRICKSTER_LAYER=overlay\n'
          'TRICKSTER_NAMESPACE=trickster-test\n'
          'TRICKSTER_KEYBOARD=exclusive\n'
          'TRICKSTER_ACCENT=#ff0000\n';
      final config = SessionConfig.parse(source);
      expect(config.layer, TricksterLayer.overlay);
      expect(config.namespace, 'trickster-test');
      expect(config.keyboard, TricksterKeyboard.exclusive);
      expect(config.accent?.toARGB32(), 0xffff0000);
    });

    test('rejects bad enum values', () {
      expect(
        () => SessionConfig.parse('TRICKSTER_LAYER=sideways\n'),
        throwsFormatException,
      );
      expect(
        () => SessionConfig.parse('TRICKSTER_ACCENT=red\n'),
        throwsFormatException,
      );
    });
  });

  group('BarSettings', () {
    test('round-trips through json', () {
      const settings = BarSettings(revision: 3, modules: ['clock', 'cpu']);
      final decoded = BarSettings.decode(settings.encode());
      expect(decoded.revision, 3);
      expect(decoded.modules, ['clock', 'cpu']);
    });

    test('rejects non-positive revisions', () {
      expect(
        () => BarSettings.decode('{"revision": 0, "modules": []}'),
        throwsFormatException,
      );
      expect(() => BarSettings.decode('[]'), throwsFormatException);
    });

    test('the retired workspaces chain keys are dropped', () {
      // Chain settings retired: old documents still decode, their keys are
      // dropped, and workspace placement belongs to the compositor. Only the
      // pip look survives in the section.
      const legacy =
          '{"revision": 1, "workspaces": {'
          '"workspace_count": 7, '
          '"per_output": {"HDMI-A-1": 6}, '
          '"display_order": ["HDMI-A-1", "HDMI-A-2"]}}';
      final decoded = BarSettings.decode(legacy);
      expect(decoded.revision, 1);
      expect(decoded.workspaces.pipStyle, PipStyle.number);
      final encoded = decoded.encode();
      expect(encoded, isNot(contains('workspace_count')));
      expect(encoded, isNot(contains('per_output')));
      expect(encoded, isNot(contains('display_order')));
    });

    test('per-display appearance round-trips and falls back', () {
      const settings = BarSettings(
        revision: 2,
        accent: Color(0xff112233),
        accentSource: AccentSource.custom,
        accentWallpaperPick: '#445566',
        displayAppearance: {
          'HDMI-A-1': DisplayAppearance(
            accent: Color(0xff778899),
            accentSource: AccentSource.wallpaper,
            accentWallpaperPick: '#AABBCC',
          ),
          'HDMI-A-2': DisplayAppearance(accentSource: AccentSource.custom),
        },
      );
      final decoded = BarSettings.decode(settings.encode());
      expect(decoded.displayAppearance.length, 2);
      expect(decoded.accentFor('HDMI-A-1'), const Color(0xff778899));
      expect(decoded.accentSourceFor('HDMI-A-1'), AccentSource.wallpaper);
      expect(decoded.accentWallpaperPickFor('HDMI-A-1'), '#AABBCC');
      // Unset fields fall back to the global keys.
      expect(decoded.accentFor('HDMI-A-2'), const Color(0xff112233));
      expect(decoded.accentWallpaperPickFor('HDMI-A-2'), '#445566');
      expect(decoded.accentSourceFor('HDMI-A-2'), AccentSource.custom);
      expect(decoded.accentFor('eDP-1'), const Color(0xff112233));
      expect(decoded.usesWallpaperAccent, isTrue);

      expect(
        () => BarSettings.decode(
          '{"revision": 1, "display_appearance": {"HDMI-A-1": 3}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "display_appearance": '
          '{"HDMI-A-1": {"accent": "nope"}}}',
        ),
        throwsFormatException,
      );
    });

    test('module placement round-trips and validates', () {
      const settings = BarSettings(
        revision: 2,
        modulePlacement: {
          'tray': ModuleZone.trailing,
          'clock': ModuleZone.leading,
        },
      );
      final decoded = BarSettings.decode(settings.encode());
      expect(decoded.modulePlacement, {
        'tray': ModuleZone.trailing,
        'clock': ModuleZone.leading,
      });
      expect(decoded.zoneFor('tray'), ModuleZone.trailing);
      const bare = BarSettings();
      expect(bare.zoneFor('tray'), ModuleZone.leading);
      expect(bare.zoneFor('workspaces'), ModuleZone.center);
      expect(bare.zoneFor('clock'), ModuleZone.trailing);
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "module_placement": {"tray": "left"}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode('{"revision": 1, "module_placement": []}'),
        throwsFormatException,
      );
    });

    test('module options round-trip and validate', () {
      const settings = BarSettings(
        revision: 4,
        cpu: CpuOptions(
          warn: 0.7,
          critical: 0.9,
          captionSource: MeterCaptionSource.device,
          sparkline: false,
        ),
        clock: ClockOptions(format: ClockFormat.hour24, showDate: false),
        battery: BatteryOptions(warn: 30, critical: 15),
        gpu: GpuOptions(
          captionSource: MeterCaptionSource.device,
          sparkline: false,
        ),
        appearance: AppearanceOptions(blur: false),
      );
      final decoded = BarSettings.decode(settings.encode());
      expect(decoded.cpu.warn, 0.7);
      expect(decoded.cpu.critical, 0.9);
      expect(decoded.clock.format, ClockFormat.hour24);
      expect(decoded.clock.showDate, isFalse);
      expect(decoded.battery.warn, 30);
      expect(decoded.battery.critical, 15);
      expect(decoded.cpu.captionSource, MeterCaptionSource.device);
      expect(decoded.cpu.sparkline, isFalse);
      expect(decoded.gpu.captionSource, MeterCaptionSource.device);
      expect(decoded.gpu.sparkline, isFalse);
      expect(decoded.appearance.blur, isFalse);
      const bare = BarSettings();
      expect(bare.cpu.warn, 0.85);
      expect(bare.clock.format, ClockFormat.locale);
      expect(bare.clock.showDate, isTrue);
      expect(bare.battery.critical, 10);
      expect(bare.cpu.captionSource, MeterCaptionSource.generic);
      expect(bare.cpu.sparkline, isTrue);
      expect(bare.gpu.captionSource, MeterCaptionSource.generic);
      expect(bare.gpu.sparkline, isTrue);
      expect(bare.appearance.blur, isTrue);
    });

    test('pip styles round-trip and reject unknown values', () {
      for (final style in PipStyle.values) {
        final settings = BarSettings(
          workspaces: WorkspaceOptions(
            pipStyle: style,
            svgSource: 'https://example.com/pip.svg',
            imageSource: '/tmp/pip.png',
          ),
        );
        final decoded = BarSettings.decode(settings.encode());
        expect(decoded.workspaces.pipStyle, style);
        expect(decoded.workspaces.svgSource, 'https://example.com/pip.svg');
        expect(decoded.workspaces.imageSource, '/tmp/pip.png');
      }
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "workspaces": {"pip_style": "stars"}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "workspaces": {"svg_source": 7}}',
        ),
        throwsFormatException,
      );
      const bare = BarSettings();
      expect(bare.workspaces.pipStyle, PipStyle.number);
      expect(bare.workspaces.svgSource, isNull);
      expect(bare.workspaces.imageSource, isNull);
    });

    test('the retired shared meter options migrate into both meters', () {
      final decoded = BarSettings.decode(
        '{"revision": 1, "meter": {"caption_source": "device", '
        '"sparkline": false}}',
      );
      expect(decoded.cpu.captionSource, MeterCaptionSource.device);
      expect(decoded.cpu.sparkline, isFalse);
      expect(decoded.gpu.captionSource, MeterCaptionSource.device);
      expect(decoded.gpu.sparkline, isFalse);

      // Per-meter keys win over the legacy object.
      final explicit = BarSettings.decode(
        '{"revision": 1, "meter": {"caption_source": "device"}, '
        '"cpu": {"caption_source": "generic", "sparkline": true}}',
      );
      expect(explicit.cpu.captionSource, MeterCaptionSource.generic);
      expect(explicit.cpu.sparkline, isTrue);
      expect(explicit.gpu.captionSource, MeterCaptionSource.device);
    });

    test('the accent source round-trips and rejects unknown values', () {
      const settings = BarSettings(
        revision: 4,
        accentSource: AccentSource.wallpaper,
      );
      expect(
        BarSettings.decode(settings.encode()).accentSource,
        AccentSource.wallpaper,
      );
      expect(const BarSettings().accentSource, AccentSource.custom);
      expect(
        () => BarSettings.decode('{"revision": 1, "accent_source": "auto"}'),
        throwsFormatException,
      );
    });

    test('the wallpaper pick round-trips and rejects malformed hex', () {
      const settings = BarSettings(
        revision: 4,
        accentSource: AccentSource.wallpaper,
        accentWallpaperPick: '#2050e0',
      );
      expect(
        BarSettings.decode(settings.encode()).accentWallpaperPick,
        '#2050e0',
      );
      expect(const BarSettings().accentWallpaperPick, isNull);
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "accent_wallpaper_pick": "blue"}',
        ),
        throwsFormatException,
      );
    });

    test('the locale round-trips and rejects unknown tags', () {
      const settings = BarSettings(revision: 4, locale: 'zh');
      expect(BarSettings.decode(settings.encode()).locale, 'zh');
      expect(const BarSettings().locale, isNull);
      expect(
        () => BarSettings.decode('{"revision": 1, "locale": "fr"}'),
        throwsFormatException,
      );
    });

    test('invalid module options are rejected at decode', () {
      expect(
        () => BarSettings.decode('{"revision": 1, "cpu": {"warn": 2}}'),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "cpu": {"warn": 0.9, "critical": 0.5}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode('{"revision": 1, "clock": {"format": "25h"}}'),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "battery": {"warn": 5, "critical": 20}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "meter": {"caption_source": "vendor"}}',
        ),
        throwsFormatException,
      );
    });
  });

  group('Cli', () {
    test('parses flags and key=value forms', () {
      final cli = Cli.parse(['--check', '--edge=bottom']);
      expect(cli.check, isTrue);
      expect(cli.edge, 'bottom');
      expect(cli.version, isFalse);
    });

    test('rejects unknown arguments', () {
      expect(() => Cli.parse(['--frobnicate']), throwsFormatException);
    });

    test('parses the settings mode flag', () {
      final cli = Cli.parse(['--settings']);
      expect(cli.settings, isTrue);
      expect(cli.check, isFalse);
      expect(Cli.parse(const []).settings, isFalse);
    });
  });
}
