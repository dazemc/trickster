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

    test('workspace count round-trips and retires the old keys', () {
      const settings = BarSettings(
        revision: 3,
        workspaces: WorkspaceOptions(count: 7),
      );
      final decoded = BarSettings.decode(settings.encode());
      expect(decoded.workspaces.count, 7);
      const bare = BarSettings();
      expect(bare.workspaces.count, 4);
      expect(
        BarSettings.decode('{"revision": 1}').workspaces,
        const WorkspaceOptions(),
      );
      // Documents written before the count option still decode; the retired
      // keys are ignored.
      expect(
        BarSettings.decode(
          '{"revision": 1, "workspaces": {"show_empty": false, "max": 5}}',
        ).workspaces.count,
        4,
      );
    });

    test('per-display workspace counts round-trip', () {
      const settings = BarSettings(
        revision: 5,
        workspaces: WorkspaceOptions(count: 4, perOutput: {'HDMI-A-1': 6}),
      );
      final decoded = BarSettings.decode(settings.encode());
      expect(decoded.workspaces.count, 4);
      expect(decoded.workspaces.countFor('HDMI-A-1'), 6);
      expect(decoded.workspaces.countFor('eDP-1'), 4);
      expect(decoded.workspaces.countFor(null), 4);
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "workspaces": {"per_output": {"HDMI-A-1": 1}}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "workspaces": {"per_output": []}}',
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
        cpu: CpuOptions(warn: 0.7, critical: 0.9),
        clock: ClockOptions(format: ClockFormat.hour24),
        battery: BatteryOptions(warn: 30, critical: 15),
        meter: MeterOptions(captionSource: MeterCaptionSource.device),
      );
      final decoded = BarSettings.decode(settings.encode());
      expect(decoded.cpu.warn, 0.7);
      expect(decoded.cpu.critical, 0.9);
      expect(decoded.clock.format, ClockFormat.hour24);
      expect(decoded.battery.warn, 30);
      expect(decoded.battery.critical, 15);
      expect(decoded.meter.captionSource, MeterCaptionSource.device);
      const bare = BarSettings();
      expect(bare.cpu.warn, 0.85);
      expect(bare.clock.format, ClockFormat.locale);
      expect(bare.battery.critical, 10);
      expect(bare.meter.captionSource, MeterCaptionSource.generic);
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

    test('invalid workspace options are rejected at decode', () {
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "workspaces": {"workspace_count": 1}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "workspaces": {"workspace_count": 10}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode(
          '{"revision": 1, "workspaces": {"workspace_count": "4"}}',
        ),
        throwsFormatException,
      );
      expect(
        () => BarSettings.decode('{"revision": 1, "workspaces": []}'),
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
