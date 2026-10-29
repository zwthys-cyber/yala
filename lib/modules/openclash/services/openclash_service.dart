// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import '../../../models/rpc_result.dart';

typedef OpenClashExec =
    Future<dynamic> Function(String command, List<String> args);

class OpenClashException implements Exception {
  final String reason;
  const OpenClashException(this.reason);
}

class OpenClashStatus {
  final bool installed;
  final bool running;
  const OpenClashStatus({required this.installed, required this.running});
}

class OpenClashSnapshot {
  final OpenClashStatus status;
  final String? version;
  final String? mode;
  final List<OpenClashGroup> groups;
  final String? controllerError;
  const OpenClashSnapshot({
    required this.status,
    this.version,
    this.mode,
    this.groups = const [],
    this.controllerError,
  });
}

class OpenClashGroup {
  final String name;
  final String type;
  final String? selected;
  final List<String> choices;
  const OpenClashGroup({
    required this.name,
    required this.type,
    required this.selected,
    required this.choices,
  });
  bool get canSelect => type == 'Selector';
}

/// Uses authenticated RPC or router SSH, never a publicly exposed controller.
/// Credentials remain on the router and are never included in RPC output.
class OpenClashService {
  final OpenClashExec execute;
  final OpenClashExec? fallbackExecute;
  bool _usingFallback = false;
  bool get usingSshFallback => _usingFallback;
  OpenClashService(this.execute, {this.fallbackExecute});

  static String shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  Future<String> _run(String script) async {
    dynamic raw;
    if (_usingFallback) {
      raw = await fallbackExecute!('/bin/sh', ['-c', script]);
    } else {
      try {
        raw = await execute('/bin/sh', ['-c', script]);
      } catch (error) {
        final message = error.toString().toLowerCase();
        final denied =
            error is OpenClashException && error.reason == 'permission' ||
            message.contains('access denied') ||
            message.contains('permission denied');
        if (!denied || fallbackExecute == null) {
          rethrow;
        }
        _usingFallback = true;
        raw = await fallbackExecute!('/bin/sh', ['-c', script]);
      }
    }
    var result = _classify(raw);
    if (result.isPermissionDenied &&
        !_usingFallback &&
        fallbackExecute != null) {
      _usingFallback = true;
      raw = await fallbackExecute!('/bin/sh', ['-c', script]);
      result = _classify(raw);
    }
    if (!result.isSuccess) {
      throw OpenClashException(
        result.isPermissionDenied ? 'permission' : 'connection',
      );
    }
    return result.data!;
  }

  RpcResult<String> _classify(dynamic raw) {
    // Controller responses and node names are data, not RPC permission errors.
    // A command may have partly executed before failing: never retry that
    // command through another transport based on its stdout or stderr.
    final transport = RpcResult.fromUbusResponse<dynamic>(raw, (data) => data);
    if (!transport.isSuccess) {
      return RpcResult<String>(
        status: transport.status,
        errorMessage: transport.errorMessage,
        errorCode: transport.errorCode,
      );
    }
    final data = transport.data;
    if (data is! Map || (data['code'] != null && data['code'] != 0)) {
      return RpcResult.failed('Router command failed');
    }
    final output = data['stdout']?.toString() ?? '';
    if (output.trim().isEmpty) {
      return RpcResult.failed('Router command returned no output');
    }
    return RpcResult.success(output);
  }

  Future<OpenClashStatus> status() async {
    final output = await _run(r'''
installed=false; running=false
[ ! -x /etc/init.d/openclash ] || installed=true
if pidof clash_meta clash mihomo >/dev/null 2>&1; then running=true; fi
printf '{"installed":%s,"running":%s}' "$installed" "$running"
''');
    final data = jsonDecode(output) as Map<String, dynamic>;
    return OpenClashStatus(
      installed: data['installed'] == true,
      running: data['running'] == true,
    );
  }

  /// One router connection per refresh, instead of reconnecting for each field.
  Future<OpenClashSnapshot> loadSnapshot() async {
    final output = await _run(r'''
installed=false; running=false
[ ! -x /etc/init.d/openclash ] || installed=true
if pidof clash_meta clash mihomo >/dev/null 2>&1; then running=true; fi
state="\"installed\":$installed,\"running\":$running"
if [ "$installed" != true ] || [ "$running" != true ]; then
  printf '{%s}' "$state"
  exit 0
fi
fail_snapshot() {
  reason=controller
  [ "$1" != 41 ] || reason=auth
  printf '{%s,"controllerError":"%s"}' "$state" "$reason"
  exit 0
}
port=$(uci -q get openclash.config.cn_port)
port=${port:-9090}
secret=$(uci -q get openclash.config.dashboard_password)
case "$port" in *[!0-9]*) fail_snapshot 42;; esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail_snapshot 42
command -v curl >/dev/null 2>&1 || fail_snapshot 42
fetch() {
  response=$(curl --silent --connect-timeout 3 --max-time 5 --max-filesize 200000 --noproxy '*' \
    -H "Authorization: Bearer $secret" -w '\n%{http_code}' "http://127.0.0.1:$port$1" 2>/dev/null) || return 42
  code=$(printf '%s' "$response" | tail -n 1)
  case "$code" in
    2??) printf '%s' "$response" | sed '$d';;
    401|403) return 41;;
    *) return 42;;
  esac
}
version=$(fetch /version) || fail_snapshot "$?"
configs=$(fetch /configs) || fail_snapshot "$?"
proxies=$(fetch /proxies) || fail_snapshot "$?"
mode=$(printf '%s' "$configs" | jsonfilter -e '@.mode' 2>/dev/null)
case "$mode" in rule|global|direct) ;; *) mode=unknown;; esac
printf '{%s,"version":%s,"mode":"%s","proxies":%s}' "$state" "$version" "$mode" "$proxies"
''');
    final data = jsonDecode(output) as Map<String, dynamic>;
    final version = data['version'];
    final proxies = data['proxies'];
    return OpenClashSnapshot(
      status: OpenClashStatus(
        installed: data['installed'] == true,
        running: data['running'] == true,
      ),
      version: version is Map ? version['version']?.toString() : null,
      mode: data['mode']?.toString().toLowerCase(),
      groups: proxies is Map && proxies['proxies'] is Map
          ? _parseGroups(proxies['proxies'] as Map)
          : [],
      controllerError: data['controllerError']?.toString(),
    );
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    if (!{'GET', 'PATCH', 'PUT'}.contains(method) || !path.startsWith('/')) {
      throw const OpenClashException('request');
    }
    final payload = body == null
        ? ''
        : ' --data-binary ${shellQuote(jsonEncode(body))}';
    final output = await _run(
      r'''
port=$(uci -q get openclash.config.cn_port)
port=${port:-9090}
secret=$(uci -q get openclash.config.dashboard_password)
case "$port" in ''|*[!0-9]*) printf '\n000'; exit 0;; esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { printf '\n000'; exit 0; }
command -v curl >/dev/null 2>&1 || { printf '\n000'; exit 0; }
curl --silent --connect-timeout 3 --max-time 8 --noproxy '*' \
  -H "Authorization: Bearer $secret" -H 'Content-Type: application/json' \
  -w '\n%{http_code}' '''
      '-X $method$payload "http://127.0.0.1:\$port"${shellQuote(path)} 2>/dev/null',
    );
    final split = output.lastIndexOf('\n');
    if (split < 0) {
      throw const OpenClashException('controller');
    }
    final code = int.tryParse(output.substring(split + 1).trim()) ?? 0;
    if (code == 401 || code == 403) {
      throw const OpenClashException('auth');
    }
    if (code < 200 || code >= 300) {
      throw const OpenClashException('controller');
    }
    final text = output.substring(0, split).trim();
    return text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>;
  }

  Future<List<OpenClashGroup>> groups() async {
    final data = await request('GET', '/proxies');
    final proxies = data['proxies'];
    if (proxies is! Map) {
      throw const OpenClashException('controller');
    }
    return _parseGroups(proxies);
  }

  List<OpenClashGroup> _parseGroups(Map proxies) {
    final groups = <OpenClashGroup>[];
    for (final entry in proxies.entries) {
      final value = entry.value;
      if (value is! Map || value['all'] is! List) {
        continue;
      }
      groups.add(
        OpenClashGroup(
          name: entry.key.toString(),
          type: value['type']?.toString() ?? '',
          selected: value['now']?.toString(),
          choices: (value['all'] as List).whereType<String>().toList(),
        ),
      );
    }
    return groups;
  }

  Future<void> setMode(String mode) async {
    if (!{'rule', 'global', 'direct'}.contains(mode)) {
      throw const OpenClashException('request');
    }
    await request('PATCH', '/configs', {'mode': mode});
    // Match OpenClash's own mode switch persistence after controller acceptance.
    await _run(
      'uci set openclash.config.proxy_mode=${shellQuote(mode)} || exit 1; '
      'if uci -q get openclash.@overwrite[0] >/dev/null; then '
      'uci set openclash.@overwrite[0].proxy_mode=${shellQuote(mode)} || exit 1; fi; '
      'uci commit openclash && printf OK',
    );
  }

  Future<void> select(OpenClashGroup group, String node) async {
    if (!group.canSelect || !group.choices.contains(node)) {
      throw const OpenClashException('request');
    }
    await request('PUT', '/proxies/${Uri.encodeComponent(group.name)}', {
      'name': node,
    });
  }

  Future<String> serviceAction(String action) async {
    if (!{'start', 'stop', 'restart'}.contains(action)) {
      throw const OpenClashException('request');
    }
    final operation = 'yala-oc-${DateTime.now().microsecondsSinceEpoch}';
    final resultPath = '/tmp/$operation.result';
    final task =
        'trap "" HUP; umask 077; /etc/init.d/openclash $action; '
        r'rc=$?; printf "%s" "$rc" > '
        '${shellQuote(resultPath)}';
    final output = await _run(
      'test -x /etc/init.d/openclash || exit 1; '
      'sh -c ${shellQuote(task)} '
      '> /dev/null 2>&1 < /dev/null & printf ACCEPTED:$operation',
    );
    if (output.trim() != 'ACCEPTED:$operation') {
      throw const OpenClashException('connection');
    }
    return operation;
  }

  Future<bool> actionComplete(String operation) async {
    if (!RegExp(r'^yala-oc-[0-9]+$').hasMatch(operation)) {
      throw const OpenClashException('request');
    }
    final path = shellQuote('/tmp/$operation.result');
    final output = await _run(
      'if [ -f $path ]; then cat $path; rm -f $path; else printf PENDING; fi',
    );
    if (output.trim() == 'PENDING') {
      return false;
    }
    if (output.trim() != '0') {
      throw const OpenClashException('service');
    }
    return true;
  }
}
