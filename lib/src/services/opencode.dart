import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// One OpenCode Go allowance window: how much of its quota the signed-in
/// workspace has spent, whether the window is exhausted, and when it resets.
class OpencodeMeterUsage extends Equatable {
  const OpencodeMeterUsage({
    required this.percent,
    this.limited = false,
    this.resetsAt,
  });

  /// Percent of the window's allowance already used (0–100).
  final double percent;

  /// Whether OpenCode Go refuses requests until [resetsAt].
  final bool limited;

  /// When the window refills.
  final DateTime? resetsAt;

  /// Percent of the window's allowance left.
  double get remaining => (100 - percent).clamp(0, 100).toDouble();

  @override
  List<Object?> get props => [percent, limited, resetsAt];

  Map<String, Object?> toJson() => {
    'percent': percent,
    'limited': limited,
    if (resetsAt != null) 'resets_at': resetsAt!.millisecondsSinceEpoch,
  };

  static OpencodeMeterUsage? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final percent = json['percent'];
    if (percent is! num) {
      return null;
    }
    final resetsAt = json['resets_at'];
    return OpencodeMeterUsage(
      percent: percent.toDouble().clamp(0, 100).toDouble(),
      limited: json['limited'] == true,
      resetsAt: resetsAt is num
          ? DateTime.fromMillisecondsSinceEpoch(resetsAt.toInt())
          : null,
    );
  }
}

/// A Console spending budget attached to the signed-in workspace.
class OpencodeBudget extends Equatable {
  const OpencodeBudget({
    required this.id,
    required this.limit,
    required this.spent,
    this.resetsAt,
  });

  final String id;
  final double limit;
  final double spent;
  final DateTime? resetsAt;

  double get remaining => (limit - spent).clamp(0, limit).toDouble();

  @override
  List<Object?> get props => [id, limit, spent, resetsAt];

  Map<String, Object?> toJson() => {
    'id': id,
    'limit': limit,
    'spent': spent,
    if (resetsAt != null) 'resets_at': resetsAt!.millisecondsSinceEpoch,
  };

  static OpencodeBudget? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final limit = json['limit'];
    final spent = json['spent'];
    if (id is! String || limit is! num || spent is! num) {
      return null;
    }
    final resetsAt = json['resets_at'];
    return OpencodeBudget(
      id: id,
      limit: limit.toDouble(),
      spent: spent.toDouble(),
      resetsAt: resetsAt is num
          ? DateTime.fromMillisecondsSinceEpoch(resetsAt.toInt())
          : null,
    );
  }
}

/// Token and cost totals for one OpenCode session.
class OpencodeSessionUsage extends Equatable {
  const OpencodeSessionUsage({
    required this.id,
    this.title,
    this.cost = 0,
    this.input = 0,
    this.output = 0,
    this.reasoning = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
  });

  final String id;
  final String? title;
  final double cost;
  final int input;
  final int output;
  final int reasoning;
  final int cacheRead;
  final int cacheWrite;

  /// Every token the session moved: prompt, completion, reasoning, and both
  /// cache directions.
  int get totalTokens => input + output + reasoning + cacheRead + cacheWrite;

  @override
  List<Object?> get props => [
    id,
    title,
    cost,
    input,
    output,
    reasoning,
    cacheRead,
    cacheWrite,
  ];

  Map<String, Object?> toJson() => {
    'id': id,
    if (title != null) 'title': title,
    'cost': cost,
    'input': input,
    'output': output,
    'reasoning': reasoning,
    'cache_read': cacheRead,
    'cache_write': cacheWrite,
  };

  static OpencodeSessionUsage? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    int count(Object? value) => value is num ? value.toInt() : 0;
    return OpencodeSessionUsage(
      id: id,
      title: json['title'] is String ? json['title'] as String : null,
      cost: (json['cost'] is num ? (json['cost'] as num).toDouble() : 0),
      input: count(json['input']),
      output: count(json['output']),
      reasoning: count(json['reasoning']),
      cacheRead: count(json['cache_read']),
      cacheWrite: count(json['cache_write']),
    );
  }
}

/// Everything the OpenCode pill shows: the three Go allowance windows, any
/// Console budgets, and the newest session's token totals. Unavailable means
/// no running server or no signed-in workspace answered.
class OpencodeUsage extends Equatable {
  const OpencodeUsage({
    this.available = false,
    this.workspaceName,
    this.usageUrl,
    this.rolling,
    this.weekly,
    this.monthly,
    this.budgets = const <OpencodeBudget>[],
    this.session,
    this.updatedAt,
  });

  final bool available;
  final String? workspaceName;
  final String? usageUrl;
  final OpencodeMeterUsage? rolling;
  final OpencodeMeterUsage? weekly;
  final OpencodeMeterUsage? monthly;
  final List<OpencodeBudget> budgets;
  final OpencodeSessionUsage? session;
  final DateTime? updatedAt;

  @override
  List<Object?> get props => [
    available,
    workspaceName,
    usageUrl,
    rolling,
    weekly,
    monthly,
    budgets,
    session,
    updatedAt,
  ];

  Map<String, Object?> toJson() => {
    'available': available,
    if (workspaceName != null) 'workspace': workspaceName,
    if (usageUrl != null) 'usage_url': usageUrl,
    if (rolling != null) 'rolling': rolling!.toJson(),
    if (weekly != null) 'weekly': weekly!.toJson(),
    if (monthly != null) 'monthly': monthly!.toJson(),
    'budgets': [for (final budget in budgets) budget.toJson()],
    if (session != null) 'session': session!.toJson(),
    if (updatedAt != null) 'updated_at': updatedAt!.millisecondsSinceEpoch,
  };

  static OpencodeUsage fromJson(Map<String, dynamic> json) {
    List<OpencodeBudget> budgets() {
      final value = json['budgets'];
      if (value is! List) {
        return const <OpencodeBudget>[];
      }
      return [for (final entry in value) ?OpencodeBudget.fromJson(entry)];
    }

    final updatedAt = json['updated_at'];
    return OpencodeUsage(
      available: json['available'] == true,
      workspaceName: json['workspace'] is String
          ? json['workspace'] as String
          : null,
      usageUrl: json['usage_url'] is String
          ? json['usage_url'] as String
          : null,
      rolling: OpencodeMeterUsage.fromJson(json['rolling']),
      weekly: OpencodeMeterUsage.fromJson(json['weekly']),
      monthly: OpencodeMeterUsage.fromJson(json['monthly']),
      budgets: budgets(),
      session: OpencodeSessionUsage.fromJson(json['session']),
      updatedAt: updatedAt is num
          ? DateTime.fromMillisecondsSinceEpoch(updatedAt.toInt())
          : null,
    );
  }
}

/// The running OpenCode server's state document:
/// `$XDG_STATE_HOME/opencode/service.json`. It carries the loopback URL the
/// server listens on and the password its Basic auth expects. The config
/// document of the same name does not carry the port, so this is the only
/// reliable discovery source.
String opencodeServiceStatePath() {
  final state = Platform.environment['XDG_STATE_HOME'];
  final base = state == null || state.isEmpty
      ? '${Platform.environment['HOME'] ?? ''}/.local/state'
      : state;
  return '$base/opencode/service.json';
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

DateTime? _time(Object? value) =>
    value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

OpencodeMeterUsage? _meter(Object? value) {
  final map = _map(value);
  if (map == null) {
    return null;
  }
  final percent = map['percent'];
  if (percent is! num) {
    return null;
  }
  return OpencodeMeterUsage(
    percent: percent.toDouble().clamp(0, 100).toDouble(),
    limited: map['limited'] == true,
    resetsAt: _time(map['resetsAt']),
  );
}

/// Decodes `/api/experimental/usage/limits`. Null means the workspace is not
/// signed in (or the response carried no Go allowance), so there is nothing
/// to show.
@visibleForTesting
OpencodeUsage? parseOpencodeUsageLimits(Object? json) {
  final data = _map(_map(json)?['data']);
  if (data == null) {
    return null;
  }
  final go = _map(data['go']);
  final rolling = _meter(go?['rolling']);
  final weekly = _meter(go?['weekly']);
  final monthly = _meter(go?['monthly']);
  if (rolling == null && weekly == null && monthly == null) {
    return null;
  }
  final workspace = _map(data['workspace']);
  final budgets = <OpencodeBudget>[];
  final rawBudgets = data['budgets'];
  if (rawBudgets is List) {
    for (final entry in rawBudgets) {
      final map = _map(entry);
      if (map == null) {
        continue;
      }
      final id = map['id'];
      final limit = map['limit'];
      final spent = map['spent'];
      if (id is String && limit is num && spent is num) {
        budgets.add(
          OpencodeBudget(
            id: id,
            limit: limit.toDouble(),
            spent: spent.toDouble(),
            resetsAt: _time(map['resetsAt']),
          ),
        );
      }
    }
  }
  return OpencodeUsage(
    available: true,
    workspaceName: workspace?['name'] is String
        ? workspace!['name'] as String
        : null,
    usageUrl: workspace?['usageURL'] is String
        ? workspace!['usageURL'] as String
        : null,
    rolling: rolling,
    weekly: weekly,
    monthly: monthly,
    budgets: List<OpencodeBudget>.unmodifiable(budgets),
  );
}

/// Decodes the newest session from `/api/session?limit=1&order=desc`.
@visibleForTesting
OpencodeSessionUsage? parseOpencodeSessionList(Object? json) {
  final data = _map(json)?['data'];
  if (data is! List || data.isEmpty) {
    return null;
  }
  final session = _map(data.first);
  if (session == null) {
    return null;
  }
  final id = session['id'];
  if (id is! String || id.isEmpty) {
    return null;
  }
  final tokens = _map(session['tokens']);
  final cache = _map(tokens?['cache']);
  int count(Object? value) => value is num ? value.toInt() : 0;
  final title = session['title'];
  final cost = session['cost'];
  return OpencodeSessionUsage(
    id: id,
    title: title is String && title.isNotEmpty ? title : null,
    cost: cost is num ? cost.toDouble() : 0,
    input: count(tokens?['input']),
    output: count(tokens?['output']),
    reasoning: count(tokens?['reasoning']),
    cacheRead: count(cache?['read']),
    cacheWrite: count(cache?['write']),
  );
}

class _ServiceState {
  const _ServiceState({required this.url, required this.password});

  final Uri url;
  final String password;
}

/// Polls the running OpenCode server for the signed-in workspace's allowance
/// and its newest session. The module owns one sampler: no timer runs while
/// the module is disabled. The Go allowance has no push event, so the
/// interval is the only cadence; failures blank the pill rather than showing
/// a stale percentage.
class OpencodeSampler {
  OpencodeSampler({
    this.interval = const Duration(seconds: 60),
    this.timeout = const Duration(seconds: 5),
    String? statePath,
    HttpClient Function()? clientFactory,
  }) : _statePath = statePath ?? opencodeServiceStatePath(),
       _clientFactory = clientFactory ?? HttpClient.new;

  /// How often the allowance and session are re-read.
  final Duration interval;
  final Duration timeout;
  final String _statePath;
  final HttpClient Function() _clientFactory;
  final _controller = StreamController<OpencodeUsage>.broadcast();
  HttpClient? _client;
  Timer? _timer;
  var _sampling = false;

  Stream<OpencodeUsage> get snapshots => _controller.stream;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(_sample()));
    unawaited(_sample());
  }

  /// Samples immediately; the pill's click uses this after a turn.
  Future<void> refresh() => _sample();

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _client?.close(force: true);
    _client = null;
    unawaited(_controller.close());
  }

  Future<void> _sample() async {
    if (_sampling || _controller.isClosed) {
      return;
    }
    _sampling = true;
    try {
      final state = _readState();
      if (state == null) {
        _emit(const OpencodeUsage());
        return;
      }
      final client = _client ??= _clientFactory()
        ..connectionTimeout = timeout
        ..idleTimeout = const Duration(seconds: 30);
      final limits = await _getJson(
        client,
        _endpoint(state.url, '/api/experimental/usage/limits'),
        state.password,
      );
      final usage = parseOpencodeUsageLimits(limits);
      if (usage == null) {
        _emit(const OpencodeUsage());
        return;
      }
      final session = await _getJson(
        client,
        _endpoint(
          state.url,
          '/api/session',
          queryParameters: const {'limit': '1', 'order': 'desc'},
        ),
        state.password,
      );
      _emit(
        OpencodeUsage(
          available: usage.available,
          workspaceName: usage.workspaceName,
          usageUrl: usage.usageUrl,
          rolling: usage.rolling,
          weekly: usage.weekly,
          monthly: usage.monthly,
          budgets: usage.budgets,
          session: parseOpencodeSessionList(session),
          updatedAt: DateTime.now(),
        ),
      );
    } on Object {
      // A stopped or restarting server has nothing to show. The timer keeps
      // trying, and the pill reappears on the first successful poll.
      _emit(const OpencodeUsage());
    } finally {
      _sampling = false;
    }
  }

  void _emit(OpencodeUsage usage) {
    if (!_controller.isClosed) {
      _controller.add(usage);
    }
  }

  _ServiceState? _readState() {
    try {
      final file = File(_statePath);
      if (!file.existsSync()) {
        return null;
      }
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        return null;
      }
      final url = decoded['url'];
      final password = decoded['password'];
      if (url is! String || password is! String || password.isEmpty) {
        return null;
      }
      final parsed = Uri.tryParse(url);
      if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
        return null;
      }
      // The state document records the wildcard bind address; a local client
      // must dial a concrete loopback host.
      final local = parsed.host == '0.0.0.0' || parsed.host == '::'
          ? parsed.replace(host: '127.0.0.1')
          : parsed;
      return _ServiceState(url: local, password: password);
    } on Object {
      return null;
    }
  }

  Uri _endpoint(Uri base, String path, {Map<String, String>? queryParameters}) {
    return base.replace(path: path, queryParameters: queryParameters);
  }

  Future<Object?> _getJson(HttpClient client, Uri uri, String password) async {
    final request = await client.getUrl(uri).timeout(timeout);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Basic ${base64.encode(utf8.encode('opencode:$password'))}',
    );
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().timeout(timeout);
      return null;
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      if (body.length + chunk.length > 1 << 20) {
        throw const FormatException('opencode response exceeds 1 MiB');
      }
      body.add(chunk);
    }
    return jsonDecode(utf8.decode(body.takeBytes(), allowMalformed: true));
  }
}
