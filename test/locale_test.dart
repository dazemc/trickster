import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/locale.dart';

void main() {
  test('supported locales pass through', () {
    expect(
      resolveAppLocale(const Locale('de', 'DE')),
      const Locale('de', 'DE'),
    );
    expect(
      resolveAppLocale(const Locale('en', 'US')),
      const Locale('en', 'US'),
    );
  });

  test('unsupported locales fall back to English', () {
    expect(resolveAppLocale(const Locale('c')), const Locale('en', 'US'));
    expect(resolveAppLocale(const Locale('xx')), const Locale('en', 'US'));
  });
}
