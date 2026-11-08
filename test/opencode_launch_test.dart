import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/platform/opencode_app.dart';

void main() {
  test('candidates prefer explicit bin directories over PATH', () {
    final candidates = opencodeUsageCandidates(
      environment: {'XDG_BIN_HOME': '/xdg/bin', 'HOME': '/home/me'},
    );
    expect(candidates, [
      '/xdg/bin/opencode-usage',
      '/home/me/.local/bin/opencode-usage',
      '/usr/local/bin/opencode-usage',
      '/usr/bin/opencode-usage',
      'opencode-usage',
    ]);
  });

  test('candidates drop missing environment paths and keep the tail', () {
    final candidates = opencodeUsageCandidates(environment: {});
    expect(candidates, [
      '/usr/local/bin/opencode-usage',
      '/usr/bin/opencode-usage',
      'opencode-usage',
    ]);
  });

  test('the launcher stops at the first working candidate', () async {
    final calls = <String>[];
    final launched = await launchOpencodeUsage(
      environment: {'HOME': '/home/me'},
      start: (executable, arguments) async {
        calls.add(executable);
        return executable == '/home/me/.local/bin/opencode-usage';
      },
    );
    expect(launched, isTrue);
    expect(calls, ['/home/me/.local/bin/opencode-usage']);
  });

  test('the launcher falls back to the console URL', () async {
    final calls = <(String, List<String>)>[];
    final launched = await launchOpencodeUsage(
      usageUrl: 'https://opencode.ai/console/wrk_1',
      environment: {'HOME': '/home/me'},
      start: (executable, arguments) async {
        calls.add((executable, arguments));
        return executable == 'xdg-open';
      },
    );
    expect(launched, isTrue);
    expect(calls.last.$1, 'xdg-open');
    expect(calls.last.$2, ['https://opencode.ai/console/wrk_1']);
    expect(calls, hasLength(5));
  });

  test('nothing to launch and no URL reports failure', () async {
    final launched = await launchOpencodeUsage(
      environment: {'HOME': '/home/me'},
      start: (executable, arguments) async => false,
    );
    expect(launched, isFalse);
  });
}
