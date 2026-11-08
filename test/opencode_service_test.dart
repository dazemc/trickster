import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trickster/src/services/opencode.dart';
import 'package:trickster/src/state/opencode_bloc.dart';

Map<String, Object?> _limitsPayload({
  num rolling = 26,
  bool limited = false,
  List<Map<String, Object?>> budgets = const [],
}) {
  return {
    'location': {'directory': '/home/example'},
    'data': {
      'workspace': {
        'id': 'wrk_1',
        'name': 'Default',
        'usageURL': 'https://opencode.ai/console/wrk_1/activity/overview',
      },
      'go': {
        'rolling': {
          'percent': rolling,
          'limited': limited,
          'resetsAt': 1794121576000,
        },
        'weekly': {'percent': 40, 'limited': false, 'resetsAt': 1794182400000},
        'monthly': {'percent': 20, 'limited': false, 'resetsAt': 1794529208000},
      },
      'budgets': budgets,
    },
  };
}

Map<String, Object?> _sessionsPayload() {
  return {
    'data': [
      {
        'id': 'ses_1',
        'title': 'Trickster',
        'cost': 0.25,
        'tokens': {
          'input': 100,
          'output': 20,
          'reasoning': 5,
          'cache': {'read': 900, 'write': 10},
        },
      },
    ],
  };
}

void main() {
  test('usage limits decode every window and remaining percent', () {
    final usage = parseOpencodeUsageLimits(_limitsPayload())!;
    expect(usage.available, isTrue);
    expect(usage.workspaceName, 'Default');
    expect(usage.usageUrl, contains('wrk_1'));
    expect(usage.rolling!.percent, 26);
    expect(usage.rolling!.remaining, 74);
    expect(usage.rolling!.limited, isFalse);
    expect(usage.weekly!.percent, 40);
    expect(usage.monthly!.percent, 20);
    expect(usage.budgets, isEmpty);
    expect(usage.rolling!.resetsAt!.millisecondsSinceEpoch, 1794121576000);
  });

  test('usage limits decode budgets and a limited window', () {
    final usage = parseOpencodeUsageLimits(
      _limitsPayload(
        rolling: 100,
        limited: true,
        budgets: [
          {
            'id': 'budget_1',
            'limit': 20,
            'spent': 7.5,
            'resetsAt': 1794529208000,
          },
        ],
      ),
    )!;
    expect(usage.rolling!.percent, 100);
    expect(usage.rolling!.remaining, 0);
    expect(usage.rolling!.limited, isTrue);
    expect(usage.budgets.single.limit, 20);
    expect(usage.budgets.single.spent, 7.5);
    expect(usage.budgets.single.remaining, 12.5);
  });

  test('an unsigned workspace yields no usage', () {
    expect(
      parseOpencodeUsageLimits(<String, Object?>{
        'data': null,
        'location': <String, Object?>{},
      }),
      isNull,
    );
    expect(parseOpencodeUsageLimits(null), isNull);
  });

  test('the newest session decodes cost and token totals', () {
    final session = parseOpencodeSessionList(_sessionsPayload())!;
    expect(session.id, 'ses_1');
    expect(session.title, 'Trickster');
    expect(session.cost, closeTo(0.25, 1e-9));
    expect(session.input, 100);
    expect(session.output, 20);
    expect(session.reasoning, 5);
    expect(session.cacheRead, 900);
    expect(session.cacheWrite, 10);
    expect(session.totalTokens, 1035);
    expect(
      parseOpencodeSessionList(<String, Object?>{'data': <Object?>[]}),
      isNull,
    );
  });

  test('usage state round-trips through JSON', () {
    final usage = OpencodeUsage(
      available: true,
      workspaceName: 'Default',
      usageUrl: 'https://opencode.ai/console/wrk_1',
      rolling: OpencodeMeterUsage(
        percent: 26,
        limited: true,
        resetsAt: DateTime.fromMillisecondsSinceEpoch(1794121576000),
      ),
      weekly: const OpencodeMeterUsage(percent: 40),
      monthly: const OpencodeMeterUsage(percent: 20),
      budgets: [
        OpencodeBudget(
          id: 'budget_1',
          limit: 20,
          spent: 7.5,
          resetsAt: DateTime.fromMillisecondsSinceEpoch(1794529208000),
        ),
      ],
      session: const OpencodeSessionUsage(
        id: 'ses_1',
        title: 'Trickster',
        cost: 0.25,
        input: 100,
        output: 20,
        reasoning: 5,
        cacheRead: 900,
        cacheWrite: 10,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1794110000000),
    );
    final decoded = OpencodeUsage.fromJson(usage.toJson());
    expect(decoded, usage);
  });

  test('the sampler discovers state, authenticates, and emits usage', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    final expectedAuth =
        'Basic ${base64.encode(utf8.encode('opencode:secret'))}';
    server.listen((request) async {
      paths.add(request.uri.path);
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          expectedAuth) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          request.uri.path == '/api/experimental/usage/limits'
              ? _limitsPayload()
              : _sessionsPayload(),
        ),
      );
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('trickster-oc-');
    final state = File('${directory.path}/service.json');
    // The wildcard bind address must be rewritten to loopback.
    state.writeAsStringSync(
      jsonEncode({
        'url': 'http://0.0.0.0:${server.port}',
        'password': 'secret',
      }),
    );

    final sampler = OpencodeSampler(
      statePath: state.path,
      interval: const Duration(hours: 1),
    );
    final first = sampler.snapshots.first;
    sampler.start();
    final usage = await first;
    expect(usage.available, isTrue);
    expect(usage.rolling!.percent, 26);
    expect(usage.session!.totalTokens, 1035);
    expect(paths, ['/api/experimental/usage/limits', '/api/session']);

    sampler.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('a missing state document emits unavailable', () async {
    final sampler = OpencodeSampler(
      statePath: '/nonexistent/trickster/opencode/service.json',
      interval: const Duration(hours: 1),
    );
    final first = sampler.snapshots.first;
    sampler.start();
    final usage = await first;
    expect(usage.available, isFalse);
    sampler.dispose();
  });

  test('the bloc starts the sampler and emits decoded state', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          request.uri.path == '/api/experimental/usage/limits'
              ? _limitsPayload()
              : _sessionsPayload(),
        ),
      );
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('trickster-oc-');
    final state = File('${directory.path}/service.json');
    state.writeAsStringSync(
      jsonEncode({'url': 'http://127.0.0.1:${server.port}', 'password': 'x'}),
    );

    final bloc = OpencodeBloc(
      sampler: OpencodeSampler(
        statePath: state.path,
        interval: const Duration(hours: 1),
      ),
    );
    final available = bloc.stream.firstWhere((usage) => usage.available);
    bloc.add(const OpencodeStarted());
    final usage = await available;
    expect(usage.weekly!.percent, 40);
    expect(usage.session!.id, 'ses_1');

    await bloc.close();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
}
