import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/bar/clock.dart';
import 'package:trickster/src/bar/meter.dart';
import 'package:trickster/src/bar/pill.dart';
import 'package:trickster/src/config/settings.dart' show ClockFormat;
import 'package:trickster/src/locale.dart';
import 'package:trickster/src/settings/color_wheel.dart';
import 'package:trickster/src/settings/settings_theme.dart';
import 'package:trickster/src/state/clock_bloc.dart';
import 'package:trickster/src/theme/accent.dart';

import 'support/strip_harness.dart';

const _accent = WallpaperAccent(Color(0xffd0bcff));

Widget _scope(Widget child) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: TricksterLocalizationScope(
      locale: const Locale('en', 'US'),
      child: Center(child: child),
    ),
  ),
);

void main() {
  testWidgets('reduced motion settles the entrance with no stagger timer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _scope(
        const SystemBarEntrance(
          index: 4,
          horizontal: true,
          child: SizedBox.square(dimension: 20),
        ),
      ),
    );

    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(SystemBarEntrance),
        matching: find.byType(Opacity),
      ),
    );
    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(SystemBarEntrance),
        matching: find.byType(Transform),
      ),
    );
    expect(opacity.opacity, 1.0);
    expect(transform.transform.getTranslation().x, 0.0);
    // The binding fails the test if the index-4 stagger timer is still
    // pending after the tree is disposed.
  });

  testWidgets('reduced motion switches the clock on its first frame', (
    tester,
  ) async {
    final bloc = ClockBloc(now: () => DateTime(2026, 1, 1, 12, 0));
    addTearDown(bloc.close);
    await tester.pumpWidget(
      withOverlayBlocs(
        _scope(
          BlocProvider<ClockBloc>.value(
            value: bloc,
            child: const ClockPill(
              accent: _accent,
              format: ClockFormat.hour24,
              showDate: false,
            ),
          ),
        ),
      ),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
    expect(find.text('12:00'), findsOneWidget);

    bloc.add(ClockTicked(DateTime(2026, 1, 1, 12, 1)));
    await tester.pump();
    await tester.pump();
    expect(find.text('12:01'), findsOneWidget);
    expect(find.text('12:00'), findsNothing);
  });

  testWidgets('reduced motion applies meter text styles immediately', (
    tester,
  ) async {
    const other = WallpaperAccent(Color(0xff8ab4ff));
    expect(other.captionColor(), isNot(_accent.captionColor()));
    await tester.pumpWidget(
      _scope(
        const LoadMeter(
          accent: _accent,
          label: 'CPU',
          current: 0.42,
          history: [0.42],
          capacity: 8,
          sparkline: false,
        ),
      ),
    );

    final style = tester.widget<AnimatedDefaultTextStyle>(
      find.byType(AnimatedDefaultTextStyle),
    );
    expect(style.duration, Duration.zero);

    await tester.pumpWidget(
      _scope(
        const LoadMeter(
          accent: other,
          label: 'CPU',
          current: 0.42,
          history: [0.42],
          capacity: 8,
          sparkline: false,
        ),
      ),
    );
    final painted = tester.widget<DefaultTextStyle>(
      find
          .descendant(
            of: find.byType(AnimatedDefaultTextStyle),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(painted.style.color, other.captionColor());
  });

  testWidgets('reduced motion zeroes the shared settings transitions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _scope(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsCloseButton(onPressed: () {}),
            SettingsButton(label: 'Save', onPressed: () {}),
            SettingsChoiceChip(
              label: 'Option',
              selected: true,
              onPressed: () {},
            ),
            SettingsToggle(label: 'Toggle', enabled: true, onChanged: (_) {}),
            SizedBox.square(
              dimension: 120,
              child: HsvColorWheel(color: _accent.color, onChanged: (_) {}),
            ),
          ],
        ),
      ),
    );

    final containers = tester.widgetList<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(containers, hasLength(5));
    for (final container in containers) {
      expect(container.duration, Duration.zero);
    }
    final align = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
    expect(align.duration, Duration.zero);
  });
}
